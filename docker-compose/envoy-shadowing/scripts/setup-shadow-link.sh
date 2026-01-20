#!/bin/bash
# Setup shadow link between source and shadow clusters

set -e

echo "Creating demo topic on source cluster..."
docker exec redpanda-source rpk topic create demo-topic --partitions 3 --replicas 1 2>/dev/null || echo "Topic already exists"

echo "Creating shadow link..."
docker exec redpanda-shadow rpk shadow create \
  --config-file /config/shadow-link.yaml \
  --no-confirm \
  -X admin.hosts=redpanda-shadow:9644

echo "Shadow link created. Checking status..."
docker exec redpanda-shadow rpk shadow status demo-shadow-link -X admin.hosts=redpanda-shadow:9644
