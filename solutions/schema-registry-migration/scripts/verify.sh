#!/usr/bin/env bash
# Prove that the Confluent to Redpanda migration reached its end state.
#
# Run from the solution directory after `make up`, `make seed`, and
# `make migrate` (or after following the steps):
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
    v=${v%\"}; v=${v#\"}
    [ -z "${!k:-}" ] && export "$k=$v"
  done < .env
fi
SOURCE_SR=http://localhost:${CONFLUENT_SR_PORT:-38081}
DEST_SR=http://localhost:${REDPANDA_SR_PORT:-28081}
CONSOLE=http://localhost:${CONSOLE_PORT:-8180}
LINK=${SHADOW_LINK:-schema-registry-migration}
CT="Content-Type: application/vnd.schemaregistry.v1+json"

# JSON helpers without jq on the host: the fields these checks read are flat.
field() { sed -nE "s/.*\"$1\":([^,}]*).*/\1/p" | head -1 | tr -d '"'; }
sr_post_code() { curl -s -o /dev/null -w '%{http_code}' -X POST "$1/subjects/$2/versions" -H "$CT" -d '{"schema": "{\"type\":\"string\"}"}'; }
status() { rpk_exec shadow status "$LINK" "$@" 2>/dev/null </dev/null; }

# tag::checks[]
# 1. Both sides are up: the source registry, the shadow cluster, Console.
assert_cmd "source Confluent Schema Registry answers" http_ok "$SOURCE_SR/subjects"
assert_cmd "Redpanda shadow cluster is healthy" sh -c "docker compose exec -T rpk rpk cluster health | grep -Eq 'Healthy:.+true'"
assert_cmd "Redpanda Console answers" http_ok "$CONSOLE/admin/health"

# 2. The shadow link exists and is configured for API-mode schema replication.
assert_contains "shadow link $LINK replicates schemas in API mode" "shadow schema registry api" "$(rpk_exec shadow describe "$LINK" --print-registry 2>/dev/null </dev/null)"

# 3. Every subject on the source exists on the destination with the same
#    versions, schema IDs, type, compatibility, and references.
assert_cmd "every source subject matches on the destination (versions, ids, type, compatibility, references)" \
  docker compose exec -T client python3 /scripts/compare_registries.py --once
assert_eq "six subjects were migrated" 6 "$(curl -s "$SOURCE_SR/subjects" | tr ',' '\n' | grep -c '"')"

# 4. The details a migration usually gets wrong.
assert_eq "orders-value has two versions on the destination" "[1,2]" "$(curl -s "$DEST_SR/subjects/orders-value/versions")"
assert_eq "orders-value keeps BACKWARD compatibility on the destination" BACKWARD "$(curl -s "$DEST_SR/config/orders-value" | field compatibilityLevel)"
assert_eq "shipping-value keeps FULL_TRANSITIVE compatibility on the destination" FULL_TRANSITIVE "$(curl -s "$DEST_SR/config/shipping-value" | field compatibilityLevel)"
assert_eq "shipping-value v1 on the destination references address-value" address-value "$(curl -s "$DEST_SR/subjects/shipping-value/versions/1" | field subject | tail -1)"
assert_eq "the JSON Schema and Protobuf subjects keep their types" "JSON PROTOBUF" \
  "$(curl -s "$DEST_SR/subjects/warehouse-events-value/versions/latest" | field schemaType) $(curl -s "$DEST_SR/subjects/inventory-events-value/versions/latest" | field schemaType)"
assert_eq "the schema ID in every record resolves to the same schema on both registries" \
  "$(curl -s "$SOURCE_SR/subjects/orders-value/versions/latest" | field id)" "$(curl -s "$DEST_SR/subjects/orders-value/versions/latest" | field id)"

# 5. Cut-over: schema replication is paused, so the destination accepts
#    schema writes, and every topic is failed over, so it accepts records.
assert_contains "Schema Registry replication is paused" "PAUSED                             true" "$(rpk_exec shadow describe "$LINK" --print-registry 2>/dev/null </dev/null)"
assert_eq "destination Schema Registry accepts a write after cut-over (HTTP 200)" 200 "$(sr_post_code "$DEST_SR" cutover-test)"
assert_eq "all three topics are FAILED_OVER" 3 "$(status --print-topic | grep -cE '^Name: (orders|customers|shipping), State: FAILED_OVER')"

# 6. The data: every migrated record plus the one produced on Redpanda after
#    cut-over decodes from Redpanda alone.
hwm() { rpk_exec topic describe "$1" -p 2>/dev/null </dev/null | awk 'NR>1 {s+=$NF} END {print s+0}'; }
assert_eq "orders, customers, shipping hold 4, 2, 1 records on Redpanda" "4 2 1" "$(hwm orders) $(hwm customers) $(hwm shipping)"
decoded=$(docker compose exec -T -e SR_URL=http://redpanda:8081 -e BOOTSTRAP_SERVERS=redpanda:9092 client python3 /scripts/consume_topic_data.py 2>/dev/null </dev/null)
assert_contains "7 records decode from the Redpanda broker with the Redpanda registry" "7 record(s) decoded with 3 schema(s) fetched from http://redpanda:8081" "$decoded"
assert_contains "the post-cut-over order ord-2001 is among them" "key=ord-2001 schema_id=3" "$decoded"
# end::checks[]

verify_summary
