#!/usr/bin/env python3
"""
Python Kafka Producer Demo
Connects via Envoy proxy to demonstrate transparent failover
"""

import time
import sys
from datetime import datetime
from kafka import KafkaProducer
from kafka.errors import KafkaError

# Configuration
KAFKA_BROKER = 'envoy:9092'
TOPIC = 'failover-demo-topic'
MESSAGE_INTERVAL = 2  # seconds

def create_producer():
    """Create and configure Kafka producer"""
    return KafkaProducer(
        bootstrap_servers=[KAFKA_BROKER],
        client_id='python-producer',
        acks='all',  # Wait for all replicas
        retries=10,  # Increased retries for better failover handling
        retry_backoff_ms=500,  # Faster retry backoff
        request_timeout_ms=10000,  # Reduced to 10s to fail faster
        max_block_ms=15000,  # Max time to block waiting for metadata (critical for failover)
        metadata_max_age_ms=5000,  # Refresh metadata every 5 seconds (more aggressive)
        connections_max_idle_ms=20000,  # Must be larger than request_timeout_ms
        reconnect_backoff_ms=250,  # Faster reconnection attempts
        reconnect_backoff_max_ms=2000,  # Lower max backoff
        max_in_flight_requests_per_connection=5,
        value_serializer=lambda v: v.encode('utf-8'),
        key_serializer=lambda k: k.encode('utf-8') if k else None
    )

def main():
    print(f'🚀 Starting Python Kafka Producer')
    print(f'📡 Connecting to: {KAFKA_BROKER}')
    print(f'📝 Topic: {TOPIC}')
    print(f'⏱️  Message interval: {MESSAGE_INTERVAL}s')
    print(f'─' * 60)

    producer = create_producer()
    message_count = 0

    try:
        while True:
            message_count += 1
            timestamp = datetime.now().isoformat()
            message = f'Message {message_count} at {timestamp}'

            try:
                # Send message and get future
                future = producer.send(
                    TOPIC,
                    key=f'key-{message_count}',
                    value=message
                )

                # Block for 'synchronous' send
                record_metadata = future.get(timeout=15)

                timestamp_str = datetime.now().strftime('%H:%M:%S')
                print(f'✓ [{timestamp_str}] Message {message_count} delivered to partition [{record_metadata.partition}] at offset {record_metadata.offset}')

            except KafkaError as e:
                print(f'❌ [{datetime.now().strftime("%H:%M:%S")}] Error producing message {message_count}: {e}', file=sys.stderr)

            time.sleep(MESSAGE_INTERVAL)

    except KeyboardInterrupt:
        print(f'\n⏹️  Shutting down producer...')
    finally:
        # Wait for any outstanding messages to be delivered
        print('📤 Flushing remaining messages...')
        producer.flush(timeout=10)
        producer.close()
        print(f'✅ Producer stopped. Total messages produced: {message_count}')

if __name__ == '__main__':
    main()
