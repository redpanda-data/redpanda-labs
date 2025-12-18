#!/bin/bash

set -e

echo "==================================="
echo "Shadow Link Setup Script"
echo "==================================="

# Wait for clusters to be ready
echo "Waiting for source cluster to be ready..."
until rpk cluster health -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644 2>/dev/null | grep -q "Healthy.*true"; do
  echo "  Waiting for source cluster..."
  sleep 2
done
echo "Source cluster is healthy!"

echo "Waiting for shadow cluster to be ready..."
until rpk cluster health -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644 2>/dev/null | grep -q "Healthy.*true"; do
  echo "  Waiting for shadow cluster..."
  sleep 2
done
echo "Shadow cluster is healthy!"

# Verify shadow linking is enabled on both clusters
echo ""
echo "Verifying shadow linking configuration..."
SOURCE_ENABLED=$(rpk cluster config get enable_shadow_linking -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644)
SHADOW_ENABLED=$(rpk cluster config get enable_shadow_linking -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644)

echo "Source cluster shadow linking enabled: $SOURCE_ENABLED"
echo "Shadow cluster shadow linking enabled: $SHADOW_ENABLED"

# Create some demo topics on the source cluster
echo ""
echo "Creating demo topics on source cluster..."
rpk topic create demo-events -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644 --partitions 3 --replicas 1 2>/dev/null || echo "  demo-events already exists"
rpk topic create demo-metrics -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644 --partitions 1 --replicas 1 2>/dev/null || echo "  demo-metrics already exists"

echo ""
echo "Topics on source cluster:"
rpk topic list -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644

# Create the shadow link from the shadow cluster
echo ""
echo "Creating shadow link from shadow cluster..."
cd /config
if rpk shadow create --config-file shadow-link.yaml --no-confirm -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644; then
  echo ""
  echo "Shadow link created successfully!"
else
  echo ""
  echo "Shadow link already exists or creation failed - checking status..."
fi
echo ""
echo "Verifying shadow link status..."
rpk shadow status demo-shadow-link -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644

echo ""
echo "==================================="
echo "Setup Complete!"
echo "==================================="
echo "Source cluster: redpanda-source:9092 (external: localhost:19092)"
echo "Shadow cluster: redpanda-shadow:9092 (external: localhost:29092)"
echo ""
echo "Console URLs:"
echo "  Source: http://localhost:8080"
echo "  Shadow: http://localhost:8081"
echo ""
echo "To check shadow link status:"
echo "  docker exec rpk-client rpk shadow status demo-shadow-link -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644"
echo "==================================="
