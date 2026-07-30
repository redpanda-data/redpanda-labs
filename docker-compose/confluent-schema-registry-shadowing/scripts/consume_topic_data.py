#!/usr/bin/env python3
"""
Consume the Avro-encoded topic data written by produce_topic_data.py,
decoding each record by parsing the Confluent wire format by hand:

  byte 0     -> magic byte (always 0x00)
  bytes 1-4  -> big-endian uint32 schema ID
  bytes 5+   -> Avro binary body

The schema for each ID is fetched from the Schema Registry on demand and
cached. References (like shipping-value -> address-value) are resolved
recursively so fastavro can parse schemas that use named types defined
elsewhere.

By default this reads from the source Confluent Schema Registry. Point
SR_URL at the shadow cluster's Schema Registry (http://redpanda-shadow:8081)
to prove that schema IDs replicated by Shadowing resolve identically on the
destination side -- the schema ID embedded in each message's wire format
doesn't change just because the schema itself got migrated.
"""
import io
import json
import os
import struct
import sys

import fastavro
import requests
from confluent_kafka import Consumer

SR_URL = os.environ.get("SR_URL", "http://confluent-schema-registry:8081")
BOOTSTRAP_SERVERS = os.environ.get("BOOTSTRAP_SERVERS", "confluent-kafka:29092")
TOPICS = ["orders", "customers", "shipping"]
IDLE_POLLS_BEFORE_EXIT = 5


def resolve_named_schema(subject, version, named_schemas):
    resp = requests.get(f"{SR_URL}/subjects/{subject}/versions/{version}", timeout=10)
    resp.raise_for_status()
    data = resp.json()
    for ref in data.get("references", []):
        resolve_named_schema(ref["subject"], ref["version"], named_schemas)
    fastavro.parse_schema(json.loads(data["schema"]), named_schemas=named_schemas)


def parse_schema_by_id(schema_id):
    resp = requests.get(f"{SR_URL}/schemas/ids/{schema_id}", timeout=10)
    resp.raise_for_status()
    data = resp.json()
    named_schemas = {}
    for ref in data.get("references", []):
        resolve_named_schema(ref["subject"], ref["version"], named_schemas)
    return fastavro.parse_schema(json.loads(data["schema"]), named_schemas=named_schemas)


def decode(raw_bytes, schema_cache):
    magic, schema_id = struct.unpack(">bI", raw_bytes[:5])
    if magic != 0:
        raise ValueError(f"unexpected magic byte {magic!r}; not Confluent wire format")
    if schema_id not in schema_cache:
        schema_cache[schema_id] = parse_schema_by_id(schema_id)
        print(f"  (fetched and cached schema ID {schema_id} from {SR_URL})")
    return fastavro.schemaless_reader(io.BytesIO(raw_bytes[5:]), schema_cache[schema_id])


def main():
    print(f"Reading from Schema Registry: {SR_URL}")
    print(f"Reading from Kafka bootstrap: {BOOTSTRAP_SERVERS}")
    print()

    consumer = Consumer(
        {
            "bootstrap.servers": BOOTSTRAP_SERVERS,
            "group.id": "topic-data-verify",
            "auto.offset.reset": "earliest",
        }
    )
    consumer.subscribe(TOPICS)

    schema_cache = {}
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
            record = decode(msg.value(), schema_cache)
            print(f"[{msg.topic()}] key={msg.key().decode()} value={record}")
    finally:
        consumer.close()

    print()
    print("Done (stopped after several empty polls).")


if __name__ == "__main__":
    main()
