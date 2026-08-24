#!/bin/bash
# Register sample schemas and a compatibility setting on the source
# Confluent Schema Registry, to demonstrate what the shadow link replicates.
set -e

SR_URL="${SR_URL:-http://localhost:8081}"

echo "Registering 'orders-value' (Avro) on the source Confluent Schema Registry..."
curl -s -X POST "${SR_URL}/subjects/orders-value/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{
    "schema": "{\"type\":\"record\",\"name\":\"Order\",\"namespace\":\"com.redpanda.demo\",\"fields\":[{\"name\":\"order_id\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"double\"}]}"
  }'
echo

echo "Registering 'customers-value' (Avro) on the source Confluent Schema Registry..."
curl -s -X POST "${SR_URL}/subjects/customers-value/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{
    "schema": "{\"type\":\"record\",\"name\":\"Customer\",\"namespace\":\"com.redpanda.demo\",\"fields\":[{\"name\":\"customer_id\",\"type\":\"string\"},{\"name\":\"email\",\"type\":\"string\"}]}"
  }'
echo

echo "Setting BACKWARD compatibility on 'orders-value'..."
curl -s -X PUT "${SR_URL}/config/orders-value" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"compatibility": "BACKWARD"}'
echo

echo "Adding a second, compatible version of 'orders-value'..."
curl -s -X POST "${SR_URL}/subjects/orders-value/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{
    "schema": "{\"type\":\"record\",\"name\":\"Order\",\"namespace\":\"com.redpanda.demo\",\"fields\":[{\"name\":\"order_id\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"double\"},{\"name\":\"currency\",\"type\":\"string\",\"default\":\"USD\"}]}"
  }'
echo

echo
echo "Subjects on the source registry:"
curl -s "${SR_URL}/subjects"
echo
