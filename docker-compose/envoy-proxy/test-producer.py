#!/usr/bin/env python3
"""Test producer for Doc Detective tests"""
from kafka import KafkaProducer

producer = KafkaProducer(
    bootstrap_servers=['envoy:9092'],
    value_serializer=lambda v: v.encode('utf-8')
)

for i in range(3):
    producer.send('failover-demo-topic', value=f'test-{i}').get(timeout=10)

producer.close()
print('OK')
