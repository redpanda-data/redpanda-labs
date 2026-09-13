#!/usr/bin/env bash
# Wait until the orders-service offsets on the target equal the ones on the
# source. Run it after the source consumer has stopped: its committed offsets
# stand still, and the migrator's next consumer group sync (every
# OFFSET_SYNC_INTERVAL) writes the translated offsets on the target.
set -uo pipefail
cd "$(dirname "$0")/.."

timeout=${1:-120}
deadline=$(( $(date +%s) + timeout ))
while :; do
  src=$(./scripts/group-offsets.sh source)
  dst=$(./scripts/group-offsets.sh target)
  if [ -n "$src" ] && [ "$src" = "$dst" ]; then
    echo "orders-service: $(printf '%s\n' "$src" | wc -l | tr -d ' ') partitions, committed offsets identical on source and target"
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "orders-service offsets still differ after ${timeout}s" >&2
    echo "source:" >&2; printf '%s\n' "$src" | sed 's/^/  /' >&2
    echo "target:" >&2; printf '%s\n' "$dst" | sed 's/^/  /' >&2
    exit 1
  fi
  sleep 2
done
