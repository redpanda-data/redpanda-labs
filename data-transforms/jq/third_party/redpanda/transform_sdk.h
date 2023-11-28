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

#pragma once

#include <chrono>
#include <expected>
#include <format>
#include <functional>
#include <optional>
#include <sstream>
#include <string>
#include <system_error>
#include <type_traits>
#include <vector>

namespace redpanda {

/**
 * Owned variable sized byte array.
 */
using bytes = std::string;

/**
 * Unowned variable sized byte array.
 */
using bytes_view = std::string_view;

/**
 * Records may have a collection of headers attached to them.
 *
 * Headers are opaque to the broker and are purely a mechanism for the producer
 * and consumers to pass information.
 */
struct header {
  std::string key;
  std::optional<bytes> value;
};

/**
 * A record in Redpanda.
 *
 * Records are generated as the result of any transforms that act upon a
 * `record_view`.
 */
struct record {
  std::optional<bytes> key;
  std::optional<bytes> value;
  std::vector<header> headers;
};

/**
 * A zero-copy `header`.
 */
struct header_view {
  std::string_view key;
  std::optional<bytes_view> value;
};

/**
 * A zero-copy representation of a record within Redpanda.
 *
 * `review_view` are handed to [`on_record_written`] event handlers as the
 * record that Redpanda wrote.
 */
struct record_view {
  std::optional<bytes_view> key;
  std::optional<bytes_view> value;
  std::vector<header_view> headers;
  std::chrono::system_clock::time_point timestamp;
};

/**
 * An event generated after a write event within the broker.
 */
struct write_event {
  /** The record for which the event was generated for. */
  record_view record;
};

/**
 * A callback to process write events and respond with a number of records to
 * write back to the output topic.
 */
template <typename E>
using on_record_written_callback =
    std::function<std::expected<std::vector<record>, E>(write_event)>;

namespace internal {
void process(const on_record_written_callback<std::string>&);
}

/**
 * Register a callback to be fired when a record is written to the input topic.
 *
 * This callback is triggered after the record has been written and fsynced to
 * disk and the producer has been acknowledged.
 *
 * This method blocks and runs forever, it should be called from `main` and any
 * setup that is needed can be done before calling this method.
 *
 * # Example
 *
 * ```cpp
 * int main() {
 *   redpanda::on_record_written<std::string>(
 *       [](redpanda::write_event event)
 *           -> std::expected<std::vector<redpanda::record>, std::string> {
 *         redpanda::record copy;
 *         copy.key = event.record.key;
 *         copy.value = event.record.value;
 *         std::transform(event.record.headers.begin(),
 *                        event.record.headers.end(),
 *                        std::back_inserter(copy.headers),
 *                        [](redpanda::header_view header) {
 *                          redpanda::header copy;
 *                          copy.key = header.key;
 *                          copy.value = header.value;
 *                          return copy;
 *                        });
 *         return {{copy}};
 *       });
 * }
 * ```
 */
template <typename E>
void on_record_written(on_record_written_callback<E> callback) {
  internal::process([callback = std::move(callback)](write_event evt) {
    return callback(std::move(evt)).transform_error([](E err) {
      if constexpr (std::is_same_v<E, std::string>) {
        return err;
      } else if constexpr (std::is_same_v<E, std::error_code>) {
        return err.message();
      } else if constexpr (std::formattable<E, char>) {
        return std::format("{}", std::move(err));
      } else {
        std::stringstream out;
        out << std::move(err);
        return std::move(out).str();
      }
    });
  });
}

}  // namespace redpanda
