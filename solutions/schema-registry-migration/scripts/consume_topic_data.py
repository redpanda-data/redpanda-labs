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

Output is sorted by topic and key so it is the same on every run.
"""
import io
import json
import os
import struct
import sys
import uuid

import fastavro
import requests
from confluent_kafka import Consumer

SR_URL = os.environ.get("SR_URL", os.environ.get("SOURCE_SR_URL", "http://confluent-schema-registry:8081"))
BOOTSTRAP_SERVERS = os.environ.get("BOOTSTRAP_SERVERS", os.environ.get("SOURCE_BOOTSTRAP_SERVERS", "confluent-kafka:29092"))
TOPICS = ["orders", "customers", "shipping"]
# A fresh group per run, so every run reads the topics from the beginning.
GROUP_ID = os.environ.get("GROUP_ID", f"schema-registry-migration-verify-{uuid.uuid4()}")
IDLE_POLLS_BEFORE_EXIT = 5


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


def main():
    print(f"Schema Registry: {SR_URL}")
    print(f"Kafka bootstrap: {BOOTSTRAP_SERVERS}")
    consumer = Consumer({"bootstrap.servers": BOOTSTRAP_SERVERS, "group.id": GROUP_ID, "auto.offset.reset": "earliest"})
    consumer.subscribe(TOPICS)

    schema_cache = {}
    records = []
    idle_polls = 0
    try:
        while idle_polls < IDLE_POLLS_BEFORE_EXIT:
            msg = consumer.poll(1.0)
            if msg is None:
                idle_polls += 1
                continue
            if msg.error():
                print(f"consumer error: {msg.error()}", file=sys.stderr)
                continue
            idle_polls = 0
            schema_id, record = decode(msg.value(), schema_cache)
            records.append((TOPICS.index(msg.topic()), msg.key().decode(), msg.topic(), schema_id, record))
    finally:
        consumer.close()

    for _, key, topic, schema_id, record in sorted(records, key=lambda r: (r[0], r[1])):
        print(f"[{topic}] key={key} schema_id={schema_id} value={json.dumps(record, sort_keys=True)}")
    print(f"{len(records)} record(s) decoded with {len(schema_cache)} schema(s) fetched from {SR_URL}")
    return 0 if records else 1


if __name__ == "__main__":
    sys.exit(main())
