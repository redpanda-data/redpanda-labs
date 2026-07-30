#!/bin/bash
# Register more advanced Schema Registry settings on the source Confluent
# Schema Registry, to verify that shadow_schema_registry_api replicates more
# than just simple standalone Avro schemas. This adds:
#   - A schema reference (one Avro schema referencing another)
#   - A JSON Schema subject
#   - A Protobuf subject
#   - A FULL_TRANSITIVE compatibility override
#
# All of this happens on the source Confluent Schema Registry via its REST
# API only - no Confluent UI is used or required.
set -e

SR_URL="${SR_URL:-http://localhost:8081}"

echo "Registering base Avro schema 'address-value' (reference target)..."
curl -s -X POST "${SR_URL}/subjects/address-value/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{
    "schema": "{\"type\":\"record\",\"name\":\"Address\",\"namespace\":\"com.redpanda.demo\",\"fields\":[{\"name\":\"street\",\"type\":\"string\"},{\"name\":\"city\",\"type\":\"string\"},{\"name\":\"postal_code\",\"type\":\"string\"}]}"
  }'
echo

echo "Registering 'shipping-value' (Avro), which references 'address-value'..."
curl -s -X POST "${SR_URL}/subjects/shipping-value/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{
    "schema": "{\"type\":\"record\",\"name\":\"Shipping\",\"namespace\":\"com.redpanda.demo\",\"fields\":[{\"name\":\"order_id\",\"type\":\"string\"},{\"name\":\"destination\",\"type\":\"com.redpanda.demo.Address\"}]}",
    "references": [
      {"name": "com.redpanda.demo.Address", "subject": "address-value", "version": 1}
    ]
  }'
echo

echo "Setting FULL_TRANSITIVE compatibility on 'shipping-value'..."
curl -s -X PUT "${SR_URL}/config/shipping-value" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"compatibility": "FULL_TRANSITIVE"}'
echo

echo "Registering 'warehouse-events-value' (JSON Schema)..."
curl -s -X POST "${SR_URL}/subjects/warehouse-events-value/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{
    "schemaType": "JSON",
    "schema": "{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"title\":\"WarehouseEvent\",\"type\":\"object\",\"properties\":{\"sku\":{\"type\":\"string\"},\"quantity\":{\"type\":\"integer\"}},\"required\":[\"sku\",\"quantity\"]}"
  }'
echo

echo "Registering 'inventory-events-value' (Protobuf)..."
curl -s -X POST "${SR_URL}/subjects/inventory-events-value/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{
    "schemaType": "PROTOBUF",
    "schema": "syntax = \"proto3\";\npackage com.redpanda.demo;\nmessage InventoryEvent {\n  string sku = 1;\n  int32 quantity = 2;\n}\n"
  }'
echo

echo
echo "Subjects on the source registry:"
curl -s "${SR_URL}/subjects"
echo
echo
echo "References for 'shipping-value' version 1:"
curl -s "${SR_URL}/subjects/shipping-value/versions/1/referencedby"
echo
