#!/usr/bin/env python3
"""
Python Kafka Consumer Demo
Connects via Envoy proxy to demonstrate transparent failover
"""

import sys
from datetime import datetime
from kafka import KafkaConsumer
from kafka.errors import KafkaError

# Configuration
KAFKA_BROKER = 'envoy:9092'
TOPIC = 'failover-demo-topic'
GROUP_ID = 'python-consumer-group'

def create_consumer():
    """Create and configure Kafka consumer"""
    return KafkaConsumer(
        TOPIC,
        bootstrap_servers=[KAFKA_BROKER],
        client_id='python-consumer',
        group_id=GROUP_ID,
        auto_offset_reset='earliest',  # Start from beginning if no offset
        enable_auto_commit=True,
        auto_commit_interval_ms=5000,
        session_timeout_ms=12000,  # Must be less than request_timeout_ms
        heartbeat_interval_ms=4000,  # Must be less than session_timeout_ms
        request_timeout_ms=20000,  # Must be larger than session_timeout_ms
        max_poll_interval_ms=30000,  # Max time between polls
        metadata_max_age_ms=5000,  # Refresh metadata every 5 seconds (more aggressive)
        connections_max_idle_ms=30000,  # Must be larger than request_timeout_ms
        reconnect_backoff_ms=250,  # Faster reconnection attempts
        reconnect_backoff_max_ms=2000,  # Lower max backoff
        value_deserializer=lambda m: m.decode('utf-8'),
        key_deserializer=lambda k: k.decode('utf-8') if k else None
    )

def main():
    print(f'🚀 Starting Python Kafka Consumer')
    print(f'📡 Connecting to: {KAFKA_BROKER}')
    print(f'📝 Topic: {TOPIC}')
    print(f'👥 Consumer Group: {GROUP_ID}')
    print(f'─' * 60)

    consumer = create_consumer()
    message_count = 0

    try:
        print('⏳ Waiting for messages...\n')

        for message in consumer:
            message_count += 1
            timestamp = datetime.now().strftime('%H:%M:%S')

            print(f'✓ [{timestamp}] Received message {message_count}')
            print(f'  Partition: {message.partition}')
            print(f'  Offset: {message.offset}')
            print(f'  Key: {message.key}')
            print(f'  Value: {message.value}')
            print()

    except KeyboardInterrupt:
        print(f'\n⏹️  Shutting down consumer...')
    except KafkaError as e:
        print(f'❌ Consumer error: {e}', file=sys.stderr)
    finally:
        consumer.close()
        print(f'✅ Consumer stopped. Total messages consumed: {message_count}')

if __name__ == '__main__':
    main()
