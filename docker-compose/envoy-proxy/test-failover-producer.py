#!/usr/bin/env python3
"""Test producer during failover for Doc Detective tests"""
import time
from kafka import KafkaProducer
from kafka.errors import NoBrokersAvailable, KafkaTimeoutError

# Retry connection in case Envoy is still failing over
for attempt in range(5):
    try:
        producer = KafkaProducer(
            bootstrap_servers=['envoy:9092'],
            value_serializer=lambda v: v.encode('utf-8'),
            request_timeout_ms=15000
        )
        producer.send('failover-demo-topic', value='failover-test').get(timeout=15)
        producer.close()
        print('OK')
        break
    except (NoBrokersAvailable, KafkaTimeoutError):
        if attempt < 4:
            time.sleep(5)
        else:
            raise
