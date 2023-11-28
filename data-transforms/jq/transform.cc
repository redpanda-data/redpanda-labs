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

#include <jq/jq.h>
#include <redpanda/transform_sdk.h>
#include <expected>
#include <iostream>
#include <memory>
#include <print>
#include <string>
#include <utility>

using bytes = redpanda::bytes;
using bytes_view = redpanda::bytes_view;

namespace jq {

void print_callback(void* file, jv input) {
  jv dump = jv_dump_string(input, 0);  // input is freed
  std::println(static_cast<FILE*>(file), "{}", jv_string_value(dump));
  jv_free(dump);
}

constexpr int unknown_error_code = 5;

struct error {
  int code = 0;
  std::string message;

  friend std::ostream& operator<<(std::ostream& os, const error& err) {
    if (err.message.empty()) {
      return os << std::format(R"({{"code": {}}})", err.code);
    }
    return os << std::format(R"({{"code": {}, "message": "{}"}})", err.code,
                             err.message);
  }

  static error extract(jq_state* state) {
    error err;
    jv exit_code = jq_get_exit_code(state);
    if (!jv_is_valid(exit_code)) {
      err.code = 0;
    } else if (jv_get_kind(exit_code) == JV_KIND_NUMBER) {
      err.code = static_cast<int>(jv_number_value(exit_code));
    } else {
      err.code = unknown_error_code;
    }
    jv_free(exit_code);
    jv msg = jq_get_error_message(state);
    if (jv_get_kind(msg) == JV_KIND_STRING) {
      err.message = jv_string_value(msg);
    } else if (jv_get_kind(msg) == JV_KIND_NULL) {
      // no output
    } else if (jv_is_valid(msg)) {
      jv dump = jv_dump_string(jv_copy(msg), /*flags=*/0);
      err.message = jv_string_value(dump);
      jv_free(dump);
    }
    jv_free(msg);
    return err;
  }
};

class jq_processor {
 public:
  jq_processor(const jq_processor&) = delete;
  jq_processor& operator=(const jq_processor&) = delete;
  jq_processor(jq_processor&&) = delete;
  jq_processor& operator=(jq_processor&&) = delete;
  ~jq_processor() { jq_teardown(&_state); }

  static std::expected<std::unique_ptr<jq_processor>, error> create(
      const std::string& filter) {
    auto p = std::unique_ptr<jq_processor>(new jq_processor());
    if (!jq_compile(p->_state, filter.c_str())) {
      return std::unexpected(error::extract(p->_state));
    }
    return p;
  }

  std::expected<std::vector<redpanda::record>, error> process(
      redpanda::write_event event) {
    if (!event.record.value) {
      return std::unexpected(
          error{.code = 1, .message = "missing record value"});
    }
    auto result = process(*event.record.value);
    if (!result) {
      return std::unexpected(result.error());
    }
    std::vector<redpanda::record> records;
    for (bytes& output : result.value()) {
      redpanda::record copy;
      copy.key = event.record.key;
      copy.value = std::move(output);
      std::transform(event.record.headers.begin(), event.record.headers.end(),
                     std::back_inserter(copy.headers),
                     [](redpanda::header_view header) {
                       redpanda::header copy;
                       copy.key = header.key;
                       copy.value = header.value;
                       return copy;
                     });
      records.push_back(std::move(copy));
    }
    return records;
  }

  std::expected<std::vector<bytes>, error> process(bytes_view payload) {
    auto result = process_raw(payload);
    if (!result) {
      return std::unexpected(result.error());
    }
    std::vector<bytes> outputs;
    outputs.reserve(result->size());
    std::transform(result->begin(), result->end(), std::back_inserter(outputs),
                   [](jv output) {
                     jv stringified = jv_dump_string(output, /*flags=*/0);
                     const char* dump = jv_string_value(stringified);
                     int dump_len =
                         jv_string_length_bytes(jv_copy(stringified));
                     bytes value(dump, static_cast<size_t>(dump_len));
                     jv_free(stringified);
                     return value;
                   });
    return outputs;
  }

 private:
  jq_processor() : _state(jq_init()) {
    jq_set_debug_cb(_state, print_callback, stdout);
    jq_set_stderr_cb(_state, print_callback, stderr);
  }

  std::expected<std::vector<jv>, error> process_raw(bytes_view payload) {
    jv parsed =
        jv_parse_sized(payload.data(), static_cast<int>(payload.size()));
    if (jv_is_valid(parsed)) {
      return process_parsed(parsed);
    }
    std::string err_msg = "invalid json";
    if (jv_invalid_has_msg(jv_copy(parsed))) {
      jv msg = jv_invalid_get_msg(jv_copy(parsed));
      err_msg += std::format(": {}", jv_string_value(msg));
      jv_free(msg);
    } else {
      std::println(stderr, "invalid json");
    }
    jv_free(parsed);
    return std::unexpected(error{.code = 1, .message = err_msg});
  }

  std::expected<std::vector<jv>, error> process_parsed(jv input) {
    jq_start(_state, input, /*flags=*/0);  // input is freed
    std::vector<jv> results;
    while (true) {
      auto result = process_one();
      if (result) {
        results.push_back(result.value());
        continue;
      }
      error err = result.error();
      if (err.code == 0) {
        return results;
      }
      for (jv result : results) {
        jv_free(result);
      }
      return std::unexpected(err);
    }
  }

  std::expected<jv, error> process_one() {
    jv result = jq_next(_state);
    if (jv_is_valid(result)) {
      return result;
    }
    // Extract an exception message if it exists
    if (jv_invalid_has_msg(jv_copy(result))) {
      jv msg = jv_invalid_get_msg(result);  // result is freed
      error err;
      err.code = 1;
      err.message = jv_string_value(msg);
      jv_free(msg);
      return std::unexpected(std::move(err));
    }
    jv_free(result);
    return std::unexpected(error::extract(_state));
  }

  jq_state* _state;
};

std::expected<std::unique_ptr<jq_processor>, error> create_processor() {
  char* filter = std::getenv("FILTER");
  if (!filter) {
    return std::unexpected(error{.code = 1, .message = "missing FILTER"});
  }
  return jq_processor::create(filter);
}

int handle_error(error err) {
  if (!err.message.empty()) {
    std::println(stderr, "{}", err.message);
  }
  return err.code;
}

int run_transform() {
  auto proc_or_err = create_processor();
  if (!proc_or_err) {
    return handle_error(proc_or_err.error());
  }
  auto processor = std::move(proc_or_err).value();
  redpanda::on_record_written<error>([&processor](redpanda::write_event event) {
    return processor->process(std::move(event));
  });
  return 0;
}

int test_transform() {
  auto proc_or_err = create_processor();
  if (!proc_or_err) {
    return handle_error(proc_or_err.error());
  }
  auto processor = std::move(proc_or_err).value();
  for (std::string line; std::getline(std::cin, line);) {
    auto result = processor->process(line);
    if (!result) {
      return handle_error(result.error());
    }
    for (const std::string& output : result.value()) {
      std::println("{}", output);
    }
  }
  return 0;
}

}  // namespace jq

int main() {
#ifndef TESTING_MODE_ENABLED
  return jq::run_transform();
#else
  return jq::test_transform();
#endif
}
