#!/bin/bash

echo "🚀 Starting RPK-based producer test with failover support"
echo "This producer will continuously send messages and handle broker failures"
echo "Brokers: envoy:9092,envoy:9093,envoy:9094 (with automatic failover)"
echo "Press Ctrl+C to stop"
echo "=========================================="

message_count=0
consecutive_failures=0
max_failures=3

# Use all brokers in RPK for automatic failover
all_brokers="envoy:9092,envoy:9093,envoy:9094"

# Trap SIGINT and SIGTERM for clean exit
trap 'echo -e "\n🛑 Producer stopped"; exit 0' SIGINT SIGTERM

while true; do
    timestamp=$(date +%s)
    message="Test message $message_count from failover demo - timestamp: $timestamp"

    # Try to send message with retry logic
    if timeout 10 bash -c "echo '$message' | rpk topic produce failover-demo-topic --brokers '$all_brokers' 2>/dev/null"; then
        echo "✅ Sent message: $message"
        consecutive_failures=0
    else
        consecutive_failures=$((consecutive_failures + 1))
        echo "❌ Failed to send message $message_count (failure $consecutive_failures/$max_failures)"

        # If too many consecutive failures, wait longer before retrying
        if [ $consecutive_failures -ge $max_failures ]; then
            echo "⚠️  Multiple failures detected - waiting 10 seconds for failover..."
            sleep 10
            consecutive_failures=0
        else
            sleep 3
        fi
    fi

    message_count=$((message_count + 1))
    sleep 2
done