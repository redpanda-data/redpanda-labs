#!/usr/bin/env python3
"""Test producer for Doc Detective tests"""
import time
from kafka import KafkaProducer
from kafka.errors import NoBrokersAvailable

# Retry connection in case Envoy is still failing over
for attempt in range(5):
    try:
        producer = KafkaProducer(
            bootstrap_servers=['envoy:9092'],
            value_serializer=lambda v: v.encode('utf-8'),
            request_timeout_ms=15000
        )
        break
    except NoBrokersAvailable:
        if attempt < 4:
            time.sleep(10)
        else:
            raise

for i in range(5):
    producer.send('demo-topic', value=f'message-{i}').get(timeout=15)

producer.close()
print('OK')
