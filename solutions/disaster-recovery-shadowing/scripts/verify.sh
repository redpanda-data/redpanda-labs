#!/usr/bin/env bash
# Prove that Disaster Recovery Shadowing works end to end.
#
# Run from the solution directory after `make up` and `make seed`:
#   ./scripts/verify.sh
# Prints "PASS (n/n)" and exits 0, or lists the failed checks and exits 1.
# CI and the last step of the solution both gate on this exit code, so every
# claim the docs make about the running system should have a check here.
set -uo pipefail
cd "$(dirname "$0")/.."

# verify-lib.sh lives in tools/ in the repo. The published attachments and the
# release bundle carry a copy next to this script.
if [ -f ../../tools/verify-lib.sh ]; then
  . ../../tools/verify-lib.sh
elif [ -f scripts/verify-lib.sh ]; then
  . scripts/verify-lib.sh
else
  echo "verify: verify-lib.sh not found (expected ../../tools/verify-lib.sh or scripts/verify-lib.sh)" >&2
  exit 2
fi

TOPIC="disaster-recovery-shadowing.events"

# Read .env the way Compose does: a variable already set in the shell wins.
if [ -f .env ]; then
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue ;; esac
    [ -z "${!k:-}" ] && export "$k=$v"
  done < .env
fi
CONSOLE_PORT=${CONSOLE_PORT:-8080}

# 1. Services are healthy.
assert_cmd "redpanda is healthy" sh -c "docker compose exec -T rpk rpk cluster health | grep -Eq 'Healthy:.+true'"
assert_cmd "console answers" http_ok "http://localhost:${CONSOLE_PORT}/admin/health"

# 2. Topics exist with the documented shape.
partitions=$(rpk_exec topic describe "$TOPIC" -p 2>/dev/null | awk 'NR>1 {n++} END {print n+0}')
assert_eq "$TOPIC has 3 partitions" 3 "$partitions"

# 3. Data landed. Sum the high watermarks across partitions.
hwm=$(rpk_exec topic describe "$TOPIC" -p 2>/dev/null | awk 'NR>1 {s+=$NF} END {print s+0}')
assert_ge "$TOPIC holds the seeded events" "$hwm" 3

# Add one check per claim the steps make: consumer group lag is 0, a sink
# table row count matches, a dashboard answers, a dead-letter topic is empty.

verify_summary
