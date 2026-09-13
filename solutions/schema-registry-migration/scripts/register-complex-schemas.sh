#!/usr/bin/env bash
# Register the schemas that make a registry migration hard: a schema that
# references another, a subject-level compatibility override, a JSON Schema
# subject, and a Protobuf subject.
#
# Runs inside the client container (`make register-complex-schemas`). SR_URL
# defaults to the source registry; nothing here touches Redpanda.
set -euo pipefail

SR_URL="${SR_URL:-${SOURCE_SR_URL:-http://confluent-schema-registry:8081}}"
SCHEMAS="${SCHEMAS:-/schemas}"
CT="Content-Type: application/vnd.schemaregistry.v1+json"

post() { curl -fsS -X POST "$SR_URL/subjects/$1/versions" -H "$CT" -d @-; echo; }

# tag::reference[]
echo "address-value v1 (Avro, the referenced schema):"
jq -n --rawfile s "$SCHEMAS/address.avsc" '{schemaType: "AVRO", schema: $s}' | post address-value

echo "shipping-value v1 (Avro, references address-value):"
jq -n --rawfile s "$SCHEMAS/shipping.avsc" '{
    schemaType: "AVRO",
    schema: $s,
    references: [{name: "com.redpanda.demo.Address", subject: "address-value", version: 1}]
  }' | post shipping-value

echo "shipping-value compatibility FULL_TRANSITIVE:"
curl -fsS -X PUT "$SR_URL/config/shipping-value" -H "$CT" -d '{"compatibility": "FULL_TRANSITIVE"}'
echo
# end::reference[]

# tag::other-types[]
echo "warehouse-events-value v1 (JSON Schema):"
jq -n --rawfile s "$SCHEMAS/warehouse-event.json" '{schemaType: "JSON", schema: $s}' | post warehouse-events-value

echo "inventory-events-value v1 (Protobuf):"
jq -n --rawfile s "$SCHEMAS/inventory_event.proto" '{schemaType: "PROTOBUF", schema: $s}' | post inventory-events-value
# end::other-types[]

echo
echo "subjects on the source registry:"
curl -fsS "$SR_URL/subjects" | jq -c 'sort'
