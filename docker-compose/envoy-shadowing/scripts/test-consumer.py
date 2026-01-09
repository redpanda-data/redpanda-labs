#!/usr/bin/env python3
"""Test consumer for Doc Detective tests - reads from shadow via Envoy"""
import time
from kafka import KafkaConsumer
from kafka.errors import NoBrokersAvailable

# Retry connection in case Envoy is still failing over
for attempt in range(5):
    try:
        consumer = KafkaConsumer(
            'demo-topic',
            bootstrap_servers=['envoy:9092'],
            auto_offset_reset='earliest',
            consumer_timeout_ms=10000,
            value_deserializer=lambda v: v.decode('utf-8')
        )
        break
    except NoBrokersAvailable:
        if attempt < 4:
            time.sleep(10)
        else:
            raise

count = 0
for msg in consumer:
    count += 1

consumer.close()
print(f'OK: {count} messages')
