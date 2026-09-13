#!/usr/bin/env python3
"""Consume the Avro records written by produce_topic_data.py and decode each
one by parsing the Confluent wire format by hand: magic byte, 4-byte schema
ID, Avro body. The schema for each ID is fetched from the Schema Registry
the script is pointed at (SR_URL) and cached; references are resolved
recursively.

The two endpoints are independent on purpose. `make consume` reads from the
Confluent broker and resolves IDs against the Confluent registry.
`make consume-shadow-registry` still reads the Confluent broker but resolves
the same IDs against the Redpanda Schema Registry, which proves that
replication preserved the IDs embedded in every record. `make consume-redpanda`
reads both from Redpanda: the end state of the migration.

The consumer joins no consumer group: it assigns every partition of the three
topics itself, starts at the first offset, and stops when each partition has
reached the high watermark it had when the run began. That makes a run
independent of group coordination and offset commits on either cluster, and
its output is sorted by topic and key, so it is the same on every run.
"""
import io
import json
import os
import struct
import sys
import time

import fastavro
import requests
from confluent_kafka import Consumer, TopicPartition

SR_URL = os.environ.get("SR_URL", os.environ.get("SOURCE_SR_URL", "http://confluent-schema-registry:8081"))
BOOTSTRAP_SERVERS = os.environ.get("BOOTSTRAP_SERVERS", os.environ.get("SOURCE_BOOTSTRAP_SERVERS", "confluent-kafka:29092"))
TOPICS = ["orders", "customers", "shipping"]
# Upper bound for one run, so a broker that stops answering can never hang
# the step that calls this script.
DEADLINE_SECONDS = int(os.environ.get("DEADLINE_SECONDS", "60"))


def resolve_named_schema(subject, version, named_schemas):
    data = requests.get(f"{SR_URL}/subjects/{subject}/versions/{version}", timeout=10)
    data.raise_for_status()
    data = data.json()
    for ref in data.get("references", []):
        resolve_named_schema(ref["subject"], ref["version"], named_schemas)
    fastavro.parse_schema(json.loads(data["schema"]), named_schemas=named_schemas)


# tag::decode[]
def parse_schema_by_id(schema_id):
    """GET /schemas/ids/<id>: the lookup every consumer makes, against
    whichever registry SR_URL names."""
    data = requests.get(f"{SR_URL}/schemas/ids/{schema_id}", timeout=10)
    data.raise_for_status()
    data = data.json()
    named_schemas = {}
    for ref in data.get("references", []):
        resolve_named_schema(ref["subject"], ref["version"], named_schemas)
    return fastavro.parse_schema(json.loads(data["schema"]), named_schemas=named_schemas)


def decode(raw, schema_cache):
    magic, schema_id = struct.unpack(">bI", raw[:5])
    if magic != 0:
        raise ValueError(f"unexpected magic byte {magic!r}; not Confluent wire format")
    if schema_id not in schema_cache:
        schema_cache[schema_id] = parse_schema_by_id(schema_id)
    return schema_id, fastavro.schemaless_reader(io.BytesIO(raw[5:]), schema_cache[schema_id])
# end::decode[]


def assignments(consumer):
    """Every partition of the three topics, from its first offset, with the
    high watermark to read up to. Topics that do not exist yet are skipped."""
    result = []
    metadata = consumer.list_topics(timeout=10)
    for topic in TOPICS:
        if topic not in metadata.topics or metadata.topics[topic].error is not None:
            continue
        for p in metadata.topics[topic].partitions:
            low, high = consumer.get_watermark_offsets(TopicPartition(topic, p), timeout=10)
            result.append((TopicPartition(topic, p, low), high))
    return result


def main():
    print(f"Schema Registry: {SR_URL}", flush=True)
    print(f"Kafka bootstrap: {BOOTSTRAP_SERVERS}", flush=True)
    consumer = Consumer({"bootstrap.servers": BOOTSTRAP_SERVERS, "group.id": "schema-registry-migration-reader", "enable.auto.commit": False})
    targets = assignments(consumer)
    consumer.assign([tp for tp, _ in targets])
    remaining = {(tp.topic, tp.partition): high for tp, high in targets if high > tp.offset}

    schema_cache = {}
    records = []
    deadline = time.time() + DEADLINE_SECONDS
    try:
        while remaining and time.time() < deadline:
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                print(f"consumer error: {msg.error()}", file=sys.stderr, flush=True)
                continue
            schema_id, record = decode(msg.value(), schema_cache)
            records.append((TOPICS.index(msg.topic()), msg.key().decode(), msg.topic(), schema_id, record))
            key = (msg.topic(), msg.partition())
            if key in remaining and msg.offset() + 1 >= remaining[key]:
                del remaining[key]
    finally:
        consumer.close()

    for _, key, topic, schema_id, record in sorted(records, key=lambda r: (r[0], r[1])):
        print(f"[{topic}] key={key} schema_id={schema_id} value={json.dumps(record, sort_keys=True)}")
    print(f"{len(records)} record(s) decoded with {len(schema_cache)} schema(s) fetched from {SR_URL}", flush=True)
    if remaining:
        print(f"stopped after {DEADLINE_SECONDS}s with partitions still behind their high watermark: {sorted(remaining)}", file=sys.stderr, flush=True)
        return 1
    return 0 if records else 1


if __name__ == "__main__":
    sys.exit(main())
