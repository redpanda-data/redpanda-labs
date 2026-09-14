#!/usr/bin/env bash
# Print the committed offsets of the orders-service group on one cluster, one
# line per partition: "<partition> <committed offset>". Used by the cutover
# to prove the migrator translated every offset exactly.
#
#   ./scripts/group-offsets.sh source
#   ./scripts/group-offsets.sh target
set -euo pipefail
cd "$(dirname "$0")/.."

side=${1:?usage: group-offsets.sh source|target}
docker compose exec -T "rpk-$side" rpk group describe orders-service --print-commits 2>/dev/null </dev/null \
  | awk '$1 == "shop.orders" && $3 ~ /^[0-9]+$/ { print $2, $3 }' | sort -n
