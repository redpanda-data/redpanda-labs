// Copyright 2023 Redpanda Data, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "transform_sdk.h"

#include <chrono>
#include <climits>
#include <cstdint>
#include <cstdlib>
#include <print>
#include <utility>

namespace redpanda::internal {
namespace {

// NOLINTBEGIN(*-macro-usage,*-macro-parentheses)

#define RP_CONCAT(x, y) RP_CONCAT_IMPL(x, y)
#define RP_CONCAT_IMPL(x, y) x##y

#define ASSIGN_OR_RETURN(lhs, rexpr) \
  RP_ASSIGN_OR_RETURN_IMPL(RP_CONCAT(expected_tmp_, __LINE__), lhs, rexpr);

#define RP_ASSIGN_OR_RETURN_IMPL(uniq_var_name, lhs, rexpr) \
  auto uniq_var_name = (rexpr);                             \
  if (!uniq_var_name.has_value()) [[unlikely]] {            \
    return std::unexpected(uniq_var_name.error());          \
  }                                                         \
  lhs = std::move(*uniq_var_name)

// NOLINTEND(*-macro-usage,*-macro-parentheses)

namespace abi {
#ifdef __wasi__

extern "C" {
#define WASM_IMPORT(mod, name) \
  __attribute__((import_module(#mod), import_name(#name)))

WASM_IMPORT(redpanda_transform, check_abi_version_1) void check();

WASM_IMPORT(redpanda_transform, read_batch_header)
int32_t read_batch_header(int64_t* base_offset,
                          int32_t* record_count,
                          int32_t* partition_leader_epoch,
                          int16_t* attributes,
                          int32_t* last_offset_delta,
                          int64_t* base_timestamp,
                          int64_t* max_timestamp,
                          int64_t* producer_id,
                          int16_t* producer_epoch,
                          int32_t* base_sequence);

WASM_IMPORT(redpanda_transform, read_next_record)
int32_t read_next_record(uint8_t* attributes,
                         int64_t* timestamp,
                         int64_t* offset,
                         char* buf,
                         uint32_t len);

WASM_IMPORT(redpanda_transform, write_record)
int32_t write_record(char* buf, uint32_t len);

#undef WASM_IMPORT
}

#else

void check() {
  std::println(stderr, "check_abi - stub");
  std::abort();
}
int32_t read_batch_header(int64_t*,
                          int32_t*,
                          int32_t*,
                          int16_t*,
                          int32_t*,
                          int64_t*,
                          int64_t*,
                          int64_t*,
                          int16_t*,
                          int32_t*) {
  std::println(stderr, "read_batch_header - stub");
  std::abort();
}

int32_t read_next_record(uint8_t*, int64_t*, int64_t*, char*, uint32_t) {
  std::println(stderr, "read_next_record - stub");
  std::abort();
}

int32_t write_record(const char*, uint32_t) {
  std::println(stderr, "write_record - stub");
  std::abort();
}

#endif
}  // namespace abi

namespace varint {

constexpr size_t MAX_LENGTH = 10;

template <typename T>
struct decoded {
  T value;
  size_t read;
};

uint64_t zigzag_encode(int64_t num) {
  constexpr unsigned int signbit_shift = (sizeof(int64_t) * CHAR_BIT) - 1;
  return (static_cast<uint64_t>(num) << 1) ^ (num >> signbit_shift);
}

int64_t zigzag_decode(uint64_t num) {
  return static_cast<int64_t>(num >> 1) ^ -static_cast<int64_t>(num & 1);
}

std::expected<decoded<uint64_t>, std::string> read_unsigned(
    bytes_view payload) {
  uint64_t value = 0;
  unsigned int shift = 0;
  for (size_t i = 0; i < payload.size(); ++i) {
    uint8_t byte = payload[i];
    if (i >= MAX_LENGTH) {
      return std::unexpected("varint overflow");
    }
    constexpr unsigned int unsigned_bits = 0x7F;
    value |= static_cast<uint64_t>(byte & unsigned_bits) << shift;
    constexpr unsigned int sign_bit = 0x80;
    if ((byte & sign_bit) == 0) {
      return decoded{
          .value = value,
          .read = i + 1,
      };
    }
    shift += CHAR_BIT - 1;
  }
  return std::unexpected("varint short read");
}

std::expected<decoded<int64_t>, std::string> read(bytes_view payload) {
  return read_unsigned(payload).transform([](decoded<uint64_t> dec) {
    return decoded<int64_t>{
        .value = zigzag_decode(dec.value),
        .read = dec.read,
    };
  });
}

std::expected<decoded<std::optional<bytes_view>>, std::string>
read_sized_buffer(bytes_view payload) {
  ASSIGN_OR_RETURN(decoded<int64_t> result, read(payload));
  if (result.value < 0) {
    return {{.value = std::nullopt, .read = result.read}};
  }
  payload = payload.substr(result.read);
  auto buf_size = static_cast<size_t>(result.value);
  if (buf_size > payload.size()) [[unlikely]] {
    return std::unexpected("varint short buffer");
  }
  return {{
      .value = payload.substr(0, buf_size),
      .read = result.read + buf_size,
  }};
}

void write_unsigned(bytes* payload, uint64_t val) {
  constexpr auto msb = 0x80;
  while (val >= msb) {
    auto byte = static_cast<uint8_t>(val) | msb;
    val >>= CHAR_BIT - 1;
    payload->push_back(static_cast<char>(byte));
  }
  payload->push_back(static_cast<char>(val & 0xFF));
}

void write(bytes* payload, int64_t val) {
  write_unsigned(payload, zigzag_encode(val));
}

template <typename B>
void write_sized_buffer(bytes* payload, const std::optional<B>& buf) {
  if (!buf.has_value()) {
    write(payload, -1);
    return;
  }
  write(payload, static_cast<int64_t>(buf->size()));
  payload->append_range(buf.value());
}

}  // namespace varint

namespace record {

using kv_pair = std::pair<std::optional<bytes_view>, std::optional<bytes_view>>;

std::expected<varint::decoded<kv_pair>, std::string> read_kv(
    bytes_view payload) {
  ASSIGN_OR_RETURN(auto key, varint::read_sized_buffer(payload));
  payload = payload.substr(key.read);
  ASSIGN_OR_RETURN(auto value, varint::read_sized_buffer(payload));
  return {{
      .value = std::make_pair(key.value, value.value),
      .read = key.read + value.read,
  }};
}

std::expected<record_view, std::string> read_record_view(
    bytes_view payload,
    std::chrono::system_clock::time_point timestamp) {
  ASSIGN_OR_RETURN(auto kv_result, read_kv(payload));
  payload = payload.substr(kv_result.read);
  ASSIGN_OR_RETURN(auto header_count_result, varint::read(payload));
  payload = payload.substr(header_count_result.read);
  std::vector<header_view> headers;
  headers.reserve(header_count_result.value);
  for (int64_t i = 0; i < header_count_result.value; ++i) {
    ASSIGN_OR_RETURN(auto kv_result, read_kv(payload));
    payload = payload.substr(kv_result.read);
    auto [key_opt, value] = kv_result.value;
    auto key = key_opt.value_or(bytes_view{});
    headers.emplace_back(key, value);
  }
  auto [key, value] = kv_result.value;
  return {{
      .key = key,
      .value = value,
      .headers = std::move(headers),
      .timestamp = timestamp,
  }};
}

void write_record(bytes* payload, const redpanda::record& rec) {
  varint::write_sized_buffer(payload, rec.key);
  varint::write_sized_buffer(payload, rec.value);
  varint::write(payload, static_cast<int64_t>(rec.headers.size()));
  for (const auto& header : rec.headers) {
    varint::write_sized_buffer(payload, std::make_optional(header.key));
    varint::write_sized_buffer(payload, header.value);
  }
}

struct batch_header {
  int64_t base_offset;
  int32_t record_count;
  int32_t partition_leader_epoch;
  int16_t attributes;
  int32_t last_offset_delta;
  int64_t base_timestamp;
  int64_t max_timestamp;
  int64_t producer_id;
  int16_t producer_epoch;
  int32_t base_sequence;
};

}  // namespace record

void process_batch(const on_record_written_callback<std::string>& callback) {
  record::batch_header header{};
  int32_t errno_or_buf_size = abi::read_batch_header(
      &header.base_offset, &header.record_count, &header.partition_leader_epoch,
      &header.attributes, &header.last_offset_delta, &header.base_timestamp,
      &header.max_timestamp, &header.producer_id, &header.producer_epoch,
      &header.base_sequence);
  if (errno_or_buf_size < 0) [[unlikely]] {
    std::println(stderr, "failed to read batch header (errno: {})",
                 errno_or_buf_size);
    std::abort();
  }
  size_t buf_size = errno_or_buf_size;

  bytes input_buffer;
  input_buffer.resize(buf_size, 0);
  bytes output_buffer;
  for (int32_t i = 0; i < header.record_count; ++i) {
    uint8_t raw_attr = 0;
    int64_t raw_timestamp = 0;
    int64_t raw_offset = 0;
    int32_t errno_or_amt =
        abi::read_next_record(&raw_attr, &raw_timestamp, &raw_offset,
                              input_buffer.data(), input_buffer.size());
    if (errno_or_amt < 0) [[unlikely]] {
      std::println(stderr, "reading record failed (errno: {}, buffer_size: {})",
                   errno_or_amt, buf_size);
      std::abort();
    }
    size_t amt = errno_or_amt;
    std::chrono::system_clock::time_point timestamp{
        std::chrono::milliseconds{raw_timestamp}};
    auto record =
        record::read_record_view({input_buffer.data(), amt}, timestamp);
    if (!record.has_value()) [[unlikely]] {
      std::println(stderr, "deserializing record failed: {}", record.error());
      std::abort();
    }
    auto result = callback(write_event{.record = std::move(record.value())});
    if (!result.has_value()) [[unlikely]] {
      std::println(stderr, "transforming record failed: {}", result.error());
      std::abort();
    }
    for (const auto& record : result.value()) {
      output_buffer.clear();
      record::write_record(&output_buffer, record);
      int32_t errno_or_amt =
          abi::write_record(output_buffer.data(), output_buffer.size());
      if (errno_or_amt != output_buffer.size()) [[unlikely]] {
        std::println(stderr, "writing record failed with errno: {}",
                     errno_or_amt);
        std::abort();
      }
    }
  }
}

}  // namespace

void process(const on_record_written_callback<std::string>& callback) {
  abi::check();
  while (true) {
    process_batch(callback);
  }
}

}  // namespace redpanda::internal

#ifdef REDPANDA_TRANSFORM_SDK_ENABLE_TESTING

int main() {
  return 0;
}

#endif
