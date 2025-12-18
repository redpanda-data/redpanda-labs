#!/bin/bash

echo "==================================="
echo "Shadow Link Replication Status"
echo "==================================="

# Check shadow link status
echo "Shadow link details:"
rpk shadow status demo-shadow-link -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644

echo ""
echo "==================================="
echo "Topic Comparison"
echo "==================================="

# Compare topics on both clusters
echo ""
echo "Topics on SOURCE cluster:"
rpk topic list -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644

echo ""
echo "Topics on SHADOW cluster:"
rpk topic list -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644

echo ""
echo "==================================="
echo "Message Count Comparison"
echo "==================================="

# Check message counts
for topic in demo-events demo-metrics; do
  echo ""
  echo "Topic: $topic"

  SOURCE_COUNT=$(rpk topic describe $topic -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644 --print-partitions 2>/dev/null | grep -v "PARTITION" | awk '{sum += $6} END {print sum}')
  SHADOW_COUNT=$(rpk topic describe $topic -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644 --print-partitions 2>/dev/null | grep -v "PARTITION" | awk '{sum += $6} END {print sum}')

  echo "  Source messages: ${SOURCE_COUNT:-0}"
  echo "  Shadow messages: ${SHADOW_COUNT:-0}"

  if [ "${SOURCE_COUNT:-0}" -eq "${SHADOW_COUNT:-0}" ]; then
    echo "  Status: ✓ In sync"
  else
    echo "  Status: ⚠ Replication in progress or lag detected"
  fi
done

echo ""
echo "==================================="
