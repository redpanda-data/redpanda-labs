#!/usr/bin/env bash
# Prove that the disaster recovery reached its end state.
#
# Run from the solution directory after `make up` and `make seed` (or after
# following the steps):
#   ./scripts/verify.sh
# Prints "PASS (n/n)" and exits 0, or lists the failed checks and exits 1. CI
# and the last step of the solution both gate on that exit code.
#
# The source cluster is gone by the time this runs, so the checks about the
# state before and during the disaster read the facts each step recorded in
# state/ at the moment they were true. Everything else is measured live
# against the shadow cluster, Envoy, and the client.
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
    v=${v%\"}; v=${v#\"}
    [ -z "${!k:-}" ] && export "$k=$v"
  done < .env
fi
# rpk_exec targets the shadow cluster: it is the only cluster left.
RPK_SERVICE=rpk-shadow
SHADOW_CONSOLE=http://localhost:${SHADOW_CONSOLE_PORT:-8381}
LINK=${SHADOW_LINK:-disaster-recovery-shadowing}
TOPIC=${DR_TOPIC:-dr-orders}
GROUP=${DR_GROUP:-dr-consumers}

# The facts each step recorded, read inside the client container so that the
# host needs no JSON tooling.
st() { docker compose exec -T client python3 /scripts/state.py "$1" "$2" 2>/dev/null </dev/null; }
routing() { docker compose exec -T client python3 /scripts/endpoint.py --routing-only 2>/dev/null </dev/null; }
status() { rpk_exec shadow status "$LINK" "$@" 2>/dev/null </dev/null; }
hwm() { rpk_exec topic describe "$1" -p 2>/dev/null </dev/null | awk 'NR>1 {s+=$NF} END {print s+0}'; }
partitions() { rpk_exec topic describe "$1" -p 2>/dev/null </dev/null | awk 'NR>1 && NF {n++} END {print n+0}'; }

# tag::checks[]
# 1. What is left standing: the source cluster is gone, everything else is up.
assert_eq "the source cluster is not running" "" \
  "$(docker compose ps --services --status running 2>/dev/null | grep -x redpanda-source)"
assert_cmd "the shadow cluster is healthy" sh -c "docker compose exec -T rpk-shadow rpk cluster health | grep -Eq 'Healthy:.+true'"
assert_cmd "Redpanda Console for the shadow cluster answers" http_ok "$SHADOW_CONSOLE/admin/health"
assert_contains "Envoy sends clients to the shadow cluster" "Envoy is routing clients to the shadow cluster" "$(routing)"

# 2. Before the disaster: the source cluster was the writer, reached through Envoy.
assert_eq "the 12 seed orders were produced through Envoy" "envoy:9092 source 12" \
  "$(st produce-before bootstrap) $(st produce-before envoy_routing) $(st produce-before produced)"
assert_eq "the group read all 12 of them from the source cluster" "source 12" \
  "$(st consume-before envoy_routing) $(st consume-before records)"

# 3. Before the disaster: replication was at parity, record for record.
assert_eq "both clusters held the same 12 records" "12 12" \
  "$(st parity source_total) $(st parity shadow_total)"
assert_eq "every partition held the same records on both clusters" \
  "$(st parity source_watermarks)" "$(st parity shadow_watermarks)"

# 4. Before the disaster: the group's committed offsets were replicated too.
assert_eq "the group's committed offsets reached the shadow cluster unchanged" \
  "$(st offsets-before source_offsets)" "$(st offsets-before shadow_offsets)"
assert_eq "those offsets accounted for all 12 records" 12 "$(st offsets-before shadow_total)"

# 5. During the disaster: the client kept working, with no configuration change.
assert_eq "the same bootstrap address was served by the shadow cluster" "envoy:9092 shadow" \
  "$(st continuity bootstrap) $(st continuity envoy_routing)"
assert_eq "a reader still got all 12 records with the source cluster down" 12 "$(st continuity records)"
assert_eq "a write was refused while the topic was still a shadow topic" "PolicyViolationError" \
  "$(st refused-during-disaster refused)"

# 6. After failover: the shadow topics are ordinary topics and accept writes.
assert_eq "no topic of the link is still replicating" 0 \
  "$(status --print-topic | grep -c 'State: ACTIVE')"
assert_eq "$TOPIC reports FAILED_OVER" 1 \
  "$(status --print-topic | grep -c "Name: $TOPIC, State: FAILED_OVER")"
assert_eq "the Schema Registry topic came across and failed over too" 1 \
  "$(status --print-topic | grep -c 'Name: _schemas, State: FAILED_OVER')"
assert_eq "the 6 new orders were produced through the same Envoy address" "envoy:9092 shadow 6" \
  "$(st produce-after bootstrap) $(st produce-after envoy_routing) $(st produce-after produced)"

# 7. After failover: the consumer resumed instead of reprocessing.
assert_eq "the group resumed from the offsets the link replicated" \
  "$(st offsets-before shadow_offsets)" "$(st consume-after start_offsets)"
assert_eq "it read only the 6 records written after the failover" 6 "$(st consume-after records)"
assert_eq "and they were the new keys, so nothing was reprocessed" \
  '["ord-0013","ord-0014","ord-0015","ord-0016","ord-0017","ord-0018"]' "$(st consume-after keys)"

# 8. The end state on the shadow cluster: 12 replicated plus 6 new.
assert_eq "$TOPIC holds 18 records on the shadow cluster" 18 "$(hwm "$TOPIC")"
assert_eq "$TOPIC still has its 3 partitions" 3 "$(partitions "$TOPIC")"
assert_eq "the $GROUP group is committed to the end of all 18 records" 18 "$(st consume-after end_total)"
# end::checks[]

verify_summary
