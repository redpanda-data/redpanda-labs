#!/bin/bash
# Setup script for Redpanda Migrator Demo
# Creates topics in source cluster with various configurations

set -e

SOURCE_BROKERS="redpanda-source:9092"
TARGET_SCHEMA_REGISTRY="http://redpanda-target:8081"

echo "Enabling import mode on target Schema Registry..."
curl -X PUT "$TARGET_SCHEMA_REGISTRY/mode" \
  -H "Content-Type: application/json" \
  -d '{"mode":"IMPORT"}' \
  2>/dev/null
echo ""
echo "✅ Schema Registry import mode enabled!"
echo ""

echo "Creating topics in source cluster..."
echo ""

# Regular topic with multiple partitions
echo "  📝 Creating demo-orders (12 partitions, delete policy)"
rpk topic create demo-orders \
  --brokers "$SOURCE_BROKERS" \
  --partitions 12 \
  --replicas 1 \
  --topic-config retention.ms=604800000 \
  --topic-config cleanup.policy=delete \
  --topic-config compression.type=snappy

# Compacted topic (like changelog)
echo "  📝 Creating demo-user-state (6 partitions, compact policy)"
rpk topic create demo-user-state \
  --brokers "$SOURCE_BROKERS" \
  --partitions 6 \
  --replicas 1 \
  --topic-config cleanup.policy=compact \
  --topic-config min.compaction.lag.ms=60000 \
  --topic-config segment.ms=3600000

# Compacted + Delete topic
echo "  📝 Creating demo-events (8 partitions, compact,delete policy)"
rpk topic create demo-events \
  --brokers "$SOURCE_BROKERS" \
  --partitions 8 \
  --replicas 1 \
  --topic-config cleanup.policy=compact,delete \
  --topic-config retention.ms=86400000 \
  --topic-config min.compaction.lag.ms=60000

# Low partition count topic
echo "  📝 Creating demo-alerts (3 partitions)"
rpk topic create demo-alerts \
  --brokers "$SOURCE_BROKERS" \
  --partitions 3 \
  --replicas 1 \
  --topic-config retention.ms=3600000

echo ""
echo "✅ Topics created successfully!"
echo ""

# Create a test schema in Schema Registry
echo "Registering test schema in source Schema Registry..."

# Register Avro schema for demo-orders-value
curl -X POST \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{
    "schema": "{\"type\":\"record\",\"name\":\"Order\",\"namespace\":\"com.redpanda.demo\",\"fields\":[{\"name\":\"order_id\",\"type\":\"string\"},{\"name\":\"customer_id\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"double\"},{\"name\":\"timestamp\",\"type\":\"long\"}]}"
  }' \
  http://redpanda-source:8081/subjects/demo-orders-value/versions \
  2>/dev/null

# Register schema for demo-user-state-value
curl -X POST \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{
    "schema": "{\"type\":\"record\",\"name\":\"UserState\",\"namespace\":\"com.redpanda.demo\",\"fields\":[{\"name\":\"user_id\",\"type\":\"string\"},{\"name\":\"state\",\"type\":\"string\"},{\"name\":\"updated_at\",\"type\":\"long\"}]}"
  }' \
  http://redpanda-source:8081/subjects/demo-user-state-value/versions \
  2>/dev/null

echo ""
echo "✅ Schemas registered!"
echo ""

# List topics to verify
echo "Source cluster topics:"
rpk topic list --brokers "$SOURCE_BROKERS" | grep "demo-"
echo ""

# Show topic details
echo "Topic configurations:"
for topic in demo-orders demo-user-state demo-events demo-alerts; do
  echo ""
  echo "  $topic:"
  rpk topic describe "$topic" --brokers "$SOURCE_BROKERS" | grep -E "PARTITION|cleanup.policy" | head -3
done

echo ""
echo "✅ Setup complete! Migration should start automatically."
echo ""
echo "Check migration progress with: make check"
