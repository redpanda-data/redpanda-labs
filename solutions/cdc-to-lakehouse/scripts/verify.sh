#!/usr/bin/env bash
# Prove that a change in an operational database is queryable in the lakehouse.
#
# Run from the solution directory after `make up seed cdc-postgres changes`
# (or after following the steps):
#   ./scripts/verify.sh
# Prints "PASS (n/n)" and exits 0, or lists the failed checks and exits 1.
# CI and the last step of the solution both gate on this exit code.
#
# The three counts that have to agree are the point of the solution: the rows
# the databases hold plus the changes applied to them, the change events in
# the topic, and the rows in the Iceberg table.
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
CONSOLE=http://localhost:${CONSOLE_PORT:-8480}
SR=http://localhost:${REDPANDA_SR_PORT:-64081}
MINIO=http://localhost:${MINIO_API_PORT:-9100}
CATALOG=http://localhost:${ICEBERG_REST_PORT:-8581}
TOPIC=cdc_orders
BUCKET=${MINIO_BUCKET:-redpanda}

psql_q() { compose_exec postgres psql -tAq -U "${POSTGRES_USER:-pandashop}" -d "${POSTGRES_DB:-pandashop}" -c "$1" 2>/dev/null </dev/null; }
mysql_q() { compose_exec mysql mysql -N -s -u root -p"${MYSQL_ROOT_PASSWORD:-pandashop-root}" "${MYSQL_DATABASE:-pandashop}" -e "$1" 2>/dev/null </dev/null; }
running() { [ -n "$(docker ps -q -f "name=cdc-to-lakehouse-$1" 2>/dev/null)" ]; }
# summary_field <name>: one count out of the single-pass Spark summary query.
summary_field() { printf '%s\n' "$SUMMARY" | tr ' ' '\n' | sed -nE "s/^$1=([0-9]+)$/\1/p" | head -1; }

# tag::checks[]
# 1. Every piece of the stack is up: the broker, Console, the object store,
#    the Iceberg REST catalog, and the source databases.
assert_cmd "redpanda is healthy" sh -c "docker compose exec -T rpk rpk cluster health | grep -Eq 'Healthy:.+true'"
assert_cmd "Redpanda Console answers" http_ok "$CONSOLE/admin/health"
assert_cmd "MinIO answers" http_ok "$MINIO/minio/health/live"
assert_cmd "the Iceberg REST catalog answers" http_ok "$CATALOG/v1/config"
assert_eq "Postgres holds the orders table" orders "$(psql_q "SELECT tablename FROM pg_tables WHERE tablename='orders';")"

# 2. The cluster is configured for Iceberg topics against the REST catalog.
assert_contains "iceberg_enabled is true on the cluster" "true" "$(rpk_exec cluster config get iceberg_enabled 2>/dev/null </dev/null)"
assert_contains "the cluster commits to the REST catalog" "rest" "$(rpk_exec cluster config get iceberg_catalog_type 2>/dev/null </dev/null)"
assert_contains "Tiered Storage is enabled" "true" "$(rpk_exec cluster config get cloud_storage_enabled 2>/dev/null </dev/null)"

# 3. The topic writes to Iceberg from the schema, and the schema is registered.
assert_contains "$TOPIC writes Iceberg in value_schema_latest mode" "value_schema_latest" \
  "$(rpk_exec topic describe "$TOPIC" -c 2>/dev/null </dev/null | grep 'redpanda.iceberg.mode')"
assert_eq "the $TOPIC-value subject holds a JSON schema" JSON \
  "$(curl -s "$SR/subjects/$TOPIC-value/versions/latest" | sed -nE 's/.*"schemaType":"([A-Z]+)".*/\1/p')"

# 4. The databases hold what the steps left them holding: five seeded orders,
#    plus one insert and one delete from scripts/change-orders.sh.
assert_eq "Postgres holds 5 orders after the insert and the delete" 5 "$(psql_q 'SELECT count(*) FROM orders;')"

# 5. The change events reached the topic. Five snapshot rows plus three
#    changes from Postgres, and two more snapshot rows when the MySQL
#    pipeline has been started too.
expected_pg=8
expected_my=0
if running connect-mysql; then expected_my=$(mysql_q 'SELECT count(*) FROM orders;'); fi
expected=$((expected_pg + expected_my))
hwm=$(retry 30 5 sh -c "test \"\$(docker compose exec -T rpk rpk topic describe $TOPIC -p 2>/dev/null </dev/null | awk 'NR>1 {s+=\$NF} END {print s+0}')\" -ge $expected" \
  && rpk_exec topic describe "$TOPIC" -p 2>/dev/null </dev/null | awk 'NR>1 {s+=$NF} END {print s+0}')
assert_eq "$TOPIC holds $expected change events" "$expected" "$hwm"
# Whitespace is stripped so the check is about the event, not about how the
# producer chose to space its JSON.
events=$(rpk_exec topic consume "$TOPIC" --offset start --num "$expected" -f '%v' 2>/dev/null </dev/null | tr -d ' \t')
assert_contains "the topic holds an update event" '"op":"update"' "$events"
assert_contains "the topic holds a delete event" '"op":"delete"' "$events"

# 6. Redpanda wrote the Iceberg files into the object store and registered the
#    table with the catalog.
assert_cmd "the catalog lists the redpanda namespace" http_ok "$CATALOG/v1/namespaces/redpanda"
assert_cmd "the catalog holds the $TOPIC table" http_ok "$CATALOG/v1/namespaces/redpanda/tables/$TOPIC"
assert_cmd "the object store holds the table's data files" \
  sh -c "docker compose exec -T mc mc ls --recursive minio/$BUCKET 2>/dev/null | grep -q '$TOPIC.*\.parquet'"

# 7. The lakehouse agrees with the topic, change for change. Every count comes
#    from one Spark query (sql/queries.sql, tag=summary).
retry 40 6 sh -c "./scripts/lakehouse.sh count | grep -qE '^[0-9]+$' && [ \"\$(./scripts/lakehouse.sh count)\" -ge $expected ]" >/dev/null 2>&1
SUMMARY=$(./scripts/lakehouse.sh query summary | tail -1)
assert_eq "the Iceberg table holds the same $expected rows as the topic" "$expected" "$(summary_field total)"
assert_eq "8 of them came from Postgres" 8 "$(summary_field postgres)"
# `snapshot` counts the whole table, so it grows by MySQL's rows once that
# pipeline has been started. The insert, update and delete are Postgres only:
# scripts/change-orders.sh never touches MySQL.
expected_snapshot=$((5 + expected_my))
assert_eq "$expected_snapshot are snapshot rows, and there is one insert, one update, and one delete" \
  "$expected_snapshot 1 1 1" \
  "$(summary_field snapshot) $(summary_field insert) $(summary_field update) $(summary_field delete)"
assert_eq "the change log reconstructs the 5 orders Postgres holds now" 5 \
  "$(./scripts/lakehouse.sh query current_count | tail -1 | tr -d '[:space:]')"
if [ "$expected_my" -gt 0 ]; then
  assert_eq "$expected_my rows came from MySQL into the same table" "$expected_my" "$(summary_field mysql)"
fi

# 8. Nothing failed to translate: Redpanda creates a <topic>~dlq table for
#    records it cannot write, so the absence of that table is the check.
assert_cmd "Redpanda created no dead-letter table" \
  sh -c "! ./scripts/lakehouse.sh query tables | grep -q '$TOPIC~dlq'"
# end::checks[]

verify_summary
