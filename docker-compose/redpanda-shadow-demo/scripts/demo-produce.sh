#!/bin/bash

echo "==================================="
echo "Producing sample data to source cluster"
echo "==================================="

# Produce some sample events
echo "Producing events to demo-events topic..."
for i in {1..10}; do
  echo "{\"event_id\": $i, \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"message\": \"Sample event $i\"}" | \
    rpk topic produce demo-events -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644
  sleep 1
done

echo ""
echo "Producing metrics to demo-metrics topic..."
for i in {1..5}; do
  echo "{\"metric_id\": $i, \"value\": $((RANDOM % 100)), \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" | \
    rpk topic produce demo-metrics -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644
  sleep 1
done

echo ""
echo "==================================="
echo "Data production complete!"
echo "==================================="
echo ""
echo "Check data on source cluster:"
echo "  docker exec rpk-client rpk topic consume demo-events -X brokers=redpanda-source:9092 -X admin.hosts=redpanda-source:9644 --num 10"
echo ""
echo "Check data replicated to shadow cluster:"
echo "  docker exec rpk-client rpk topic consume demo-events -X brokers=redpanda-shadow:9092 -X admin.hosts=redpanda-shadow:9644 --num 10"
echo ""
echo "View in consoles:"
echo "  Source: http://localhost:8080/topics/demo-events"
echo "  Shadow: http://localhost:8081/topics/demo-events"
echo "==================================="
