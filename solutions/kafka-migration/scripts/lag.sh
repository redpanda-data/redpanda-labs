#!/usr/bin/env bash
# Print the migrator's lag per topic: how many records the source holds that
# the migrator has not yet read. Reads the Prometheus metrics of the migrator
# container and sums the redpanda_lag gauge (the migrator input's lag metric) over partitions.
#
#   ./scripts/lag.sh          one table
#   ./scripts/lag.sh --total  the total only, as a number
set -euo pipefail
cd "$(dirname "$0")/.."

metrics=$(docker compose exec -T migrator wget -qO- http://localhost:4195/metrics 2>/dev/null </dev/null || true)
if [ -z "$metrics" ]; then
  echo "lag: the migrator is not answering; is it running? (make migrate)" >&2
  exit 1
fi

# tag::awk[]
per_topic=$(printf '%s\n' "$metrics" | awk '
  /^redpanda_lag\{/ {
    match($0, /topic="[^"]*"/); t = substr($0, RSTART + 7, RLENGTH - 8)
    lag[t] += $NF
  }
  END { for (t in lag) printf "%s\t%d\n", t, lag[t] }' | sort)
# end::awk[]

if [ "${1:-}" = "--total" ]; then
  printf '%s\n' "$per_topic" | awk -F'\t' '{ s += $2 } END { print s + 0 }'
  exit 0
fi

printf 'TOPIC                    LAG\n'
printf '%s\n' "$per_topic" | awk -F'\t' '{ printf "%-24s %d\n", $1, $2 }'
printf '%s\n' "$per_topic" | awk -F'\t' '{ s += $2 } END { printf "%-24s %d\n", "TOTAL", s + 0 }'
