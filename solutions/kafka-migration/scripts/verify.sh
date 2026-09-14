#!/usr/bin/env bash
# Prove that Kafka Migration works end to end.
#
# Run from the solution directory after `make up` and `make seed` (or after
# the last cutover step of the walkthrough):
#   ./scripts/verify.sh
# Prints "PASS (n/n)" and exits 0, or lists the failed checks and exits 1.
# CI and the last step of the solution both gate on this exit code. Each check
# is one claim the steps make about the two clusters.
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

# Read .env the way Compose does: a variable already set in the shell wins.
if [ -f .env ]; then
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue ;; esac
    [ -z "${!k:-}" ] && export "$k=$v"
  done < .env
fi
CONSOLE_PORT=${CONSOLE_PORT:-8280}
MIGRATOR_PORT=${MIGRATOR_PORT:-4295}
TOPICS="shop.orders shop.customer-profiles shop.inventory-events shop.alerts"

# </dev/null: docker compose exec forwards stdin, which would eat loop input.
rpk_source() { docker compose exec -T rpk-source rpk "$@" 2>/dev/null </dev/null; }
rpk_target() { docker compose exec -T rpk-target rpk "$@" 2>/dev/null </dev/null; }
# The same rpk, authenticating as the migrator user instead of the superuser.
as_migrator() { docker compose exec -T "rpk-$1" sh -c 'rpk -X user="$MIGRATOR_USER" -X pass="$MIGRATOR_PASSWORD" "$@"' rpk "${@:2}" 2>/dev/null </dev/null; }
partitions() { rpk_"$1" topic describe "$2" -p | awk 'NR>1 {n++} END {print n+0}'; }
hwm() { rpk_"$1" topic describe "$2" -p | awk 'NR>1 {s+=$NF} END {print s+0}'; }
config() { rpk_"$1" topic describe "$2" -c | awk -v k="$3" '$1==k {print $2}'; }
# Every schema on one side: "subject version id type", sorted.
schemas() { rpk_"$1" registry schema list $(rpk_"$1" registry subject list | awk 'NR>1 && $2 ~ /^shop\./ {print $2}') | awk 'NR>1 {print $2, $3, $4, $5}' | sort; }

# tag::checks[]
# 1. Both clusters are healthy and Console and the migrator answer.
if rpk_source cluster health | grep -Eq 'Healthy:.+true' && rpk_target cluster health | grep -Eq 'Healthy:.+true'; then
  pass "source and target clusters are healthy"
else
  fail "source and target clusters are healthy"
fi
if http_ok "http://localhost:${CONSOLE_PORT}/admin/health" && http_ok "http://localhost:${MIGRATOR_PORT}/ready"; then
  pass "Console and the migrator answer"
else
  fail "Console and the migrator answer (http://localhost:${CONSOLE_PORT}, http://localhost:${MIGRATOR_PORT}/ready)"
fi

# 2. Authentication is enforced: without credentials, the source rejects the
#    request. (env -u strips the helper's RPK_* credentials.)
if docker compose exec -T rpk-source env -u RPK_USER -u RPK_PASS -u RPK_SASL_MECHANISM rpk topic list >/dev/null 2>&1 </dev/null; then
  fail "SASL is enforced: an unauthenticated client is rejected"
else
  pass "SASL is enforced: an unauthenticated client is rejected"
fi

# 3. Least privilege: the migrator can read the source but not write to it,
#    and can create only shop.* topics on the target.
if as_migrator source topic list | grep -q '^shop\.orders' && ! printf 'x\n' | docker compose exec -T rpk-source sh -c 'rpk -X user="$MIGRATOR_USER" -X pass="$MIGRATOR_PASSWORD" topic produce shop.orders' >/dev/null 2>&1; then
  pass "migrator user can read the source but not produce to it"
else
  fail "migrator user can read the source but not produce to it"
fi
if as_migrator target topic create not-migrated >/dev/null; then
  fail "migrator user cannot create topics outside shop.* on the target"
  rpk_target topic delete not-migrated >/dev/null
else
  pass "migrator user cannot create topics outside shop.* on the target"
fi

# 4. Every topic exists on the target with the same partition count and the
#    same cleanup policy and retention.
shape_src=""; shape_dst=""
for t in $TOPICS; do
  shape_src="$shape_src $t=$(partitions source "$t")/$(config source "$t" cleanup.policy)/$(config source "$t" retention.ms)"
  shape_dst="$shape_dst $t=$(partitions target "$t")/$(config target "$t" cleanup.policy)/$(config target "$t" retention.ms)"
done
assert_eq "topics: partitions, cleanup.policy, and retention.ms match on all four topics" "$shape_src" "$shape_dst"

# 5. Every record is on the target: high watermarks are equal per topic. The
#    producer has stopped by now; the retry covers the migrator's last batch.
hwms() { for t in $TOPICS; do printf '%s=%s ' "$t" "$(hwm "$1" "$t")"; done; }
retry 30 2 sh -c '[ "$(./scripts/lag.sh --total 2>/dev/null)" = 0 ]' >/dev/null
assert_eq "records: high watermarks match on every topic" "$(hwms source)" "$(hwms target)"
assert_ge "records: shop.orders holds records" "$(hwm source shop.orders)" 1

# 6. Schemas: the same subjects, versions, and IDs on both registries, and
#    shop.orders-value has the version registered after the migrator started.
retry 10 2 sh -c '[ "$(docker compose exec -T rpk-source rpk registry schema list shop.orders-value 2>/dev/null </dev/null | wc -l)" = "$(docker compose exec -T rpk-target rpk registry schema list shop.orders-value 2>/dev/null </dev/null | wc -l)" ]' >/dev/null
assert_eq "schemas: subjects, versions, and IDs match" "$(schemas source)" "$(schemas target)"
assert_eq "schemas: shop.orders-value has 2 versions on the target" 2 "$(rpk_target registry schema list shop.orders-value | awk 'NR>1' | wc -l | tr -d ' ')"

# 7. Consumer group: the committed offsets of orders-service were translated
#    exactly (records are timestamped 20 ms apart, so each maps to itself),
#    and the consumer that moved to the target has caught up there.
src_offsets=$(./scripts/group-offsets.sh source)
assert_eq "consumer group: orders-service has committed offsets on 12 source partitions" 12 "$(printf '%s\n' "$src_offsets" | grep -c .)"
dst_group=$(rpk_target group describe orders-service)
state=$(printf '%s\n' "$dst_group" | awk '$1=="STATE" {print $2}')
retry 30 2 sh -c '[ "$(docker compose exec -T rpk-target rpk group describe orders-service 2>/dev/null </dev/null | awk "\$1==\"TOTAL-LAG\" {print \$2}")" = 0 ]' >/dev/null
lag=$(rpk_target group describe orders-service | awk '$1=="TOTAL-LAG" {print $2}')
if [ "$state" = "Stable" ] && [ "$lag" = 0 ]; then
  pass "consumer group: orders-service is Stable on the target with lag 0"
else
  fail "consumer group: orders-service is Stable on the target with lag 0 (state $state, lag $lag)"
fi
# The translated offsets are recorded before the target consumer moves them:
# the cutover step captured them in steps/finish-cutover/expected; here, the
# target's offsets are at least the source's on every partition (never behind).
behind=$(paste <(printf '%s\n' "$src_offsets") <(./scripts/group-offsets.sh target) | awk '$4 < $2 {n++} END {print n+0}')
assert_eq "consumer group: no target partition is behind the source's committed offset" 0 "$behind"

# 8. The target Schema Registry is back in READWRITE mode.
assert_contains "target Schema Registry mode is READWRITE" READWRITE "$(rpk_target registry mode get)"
# end::checks[]

verify_summary
