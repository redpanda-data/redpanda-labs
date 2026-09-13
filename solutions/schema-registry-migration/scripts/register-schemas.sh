#!/usr/bin/env bash
# Register the first schemas on the source Confluent Schema Registry, the way
# an application team would have over the years: two Avro subjects, a
# compatibility rule, and a second version of one of them.
#
# Runs inside the client container (`make register-schemas`), where curl and
# jq are installed and the schema files are mounted at /schemas. SR_URL
# defaults to the source registry; nothing here touches Redpanda.
set -euo pipefail

SR_URL="${SR_URL:-${SOURCE_SR_URL:-http://confluent-schema-registry:8081}}"
SCHEMAS="${SCHEMAS:-/schemas}"
CT="Content-Type: application/vnd.schemaregistry.v1+json"

# tag::register[]
# post_schema <subject> <schema file> [schemaType]
# Wraps the file in the registry's request body and posts it as a new version.
post_schema() {
  local subject=$1 file=$2 type=${3:-AVRO}
  jq -n --rawfile s "$file" --arg t "$type" '{schemaType: $t, schema: $s}' \
    | curl -fsS -X POST "$SR_URL/subjects/$subject/versions" -H "$CT" -d @-
  echo
}

echo "orders-value v1 (Avro):"
post_schema orders-value "$SCHEMAS/orders-v1.avsc"

echo "customers-value v1 (Avro):"
post_schema customers-value "$SCHEMAS/customers.avsc"

echo "orders-value compatibility BACKWARD:"
curl -fsS -X PUT "$SR_URL/config/orders-value" -H "$CT" -d '{"compatibility": "BACKWARD"}'
echo

echo "orders-value v2 (adds currency with a default, so BACKWARD accepts it):"
post_schema orders-value "$SCHEMAS/orders-v2.avsc"
# end::register[]

echo
echo "subjects on the source registry:"
curl -fsS "$SR_URL/subjects" | jq -c 'sort'
