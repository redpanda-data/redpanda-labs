#!/usr/bin/env python3
"""Produce Avro records in the Confluent wire format, using schemas that are
already registered.

This is the application side of the migration. It looks each subject up in
the Schema Registry it is pointed at (SR_URL), encodes each record with
fastavro, and frames it the way every Confluent-compatible serializer does:

  byte 0     magic byte 0x00
  bytes 1-4  the schema ID, big-endian
  bytes 5+   the Avro binary body

Subjects follow the default TopicNameStrategy: topic + "-value".

  orders    -> orders-value     (latest version, which has a default for currency)
  customers -> customers-value
  shipping  -> shipping-value   (references address-value)

Before cutover, `make produce` runs it against the Confluent broker and
registry with the seed data. After cutover, `make produce-redpanda` runs it
against the Redpanda cluster and its Schema Registry with
sample-data/orders-after-cutover.json: the same code, different endpoints.
"""
import io
import json
import os
import struct
import sys

import fastavro
import requests
from confluent_kafka import Producer

SR_URL = os.environ.get("SR_URL", os.environ.get("SOURCE_SR_URL", "http://confluent-schema-registry:8081"))
BOOTSTRAP_SERVERS = os.environ.get("BOOTSTRAP_SERVERS", os.environ.get("SOURCE_BOOTSTRAP_SERVERS", "confluent-kafka:29092"))
DATA_DIR = os.environ.get("DATA_DIR", "/sample-data")
# Which files to produce: "seed" is the pre-cutover data set, "cutover" the
# one order written to Redpanda after the applications moved.
DATASET = sys.argv[1] if len(sys.argv) > 1 else "seed"

DATASETS = {
    "seed": [("orders", "orders.json", "order_id"), ("customers", "customers.json", "customer_id"), ("shipping", "shipping.json", "order_id")],
    "cutover": [("orders", "orders-after-cutover.json", "order_id")],
}

MAGIC_BYTE = 0


# tag::schema[]
def resolve_named_schema(subject, version, named_schemas):
    """Parse a subject's schema and, recursively, every schema it references,
    so fastavro knows the named types (com.redpanda.demo.Address) that a
    referencing schema uses."""
    data = requests.get(f"{SR_URL}/subjects/{subject}/versions/{version}", timeout=10)
    data.raise_for_status()
    data = data.json()
    for ref in data.get("references", []):
        resolve_named_schema(ref["subject"], ref["version"], named_schemas)
    fastavro.parse_schema(json.loads(data["schema"]), named_schemas=named_schemas)


def load_schema(subject):
    """The latest schema ID of a subject and its parsed schema, references
    resolved."""
    latest = requests.get(f"{SR_URL}/subjects/{subject}/versions/latest", timeout=10)
    latest.raise_for_status()
    latest = latest.json()
    named_schemas = {}
    for ref in latest.get("references", []):
        resolve_named_schema(ref["subject"], ref["version"], named_schemas)
    parsed = fastavro.parse_schema(json.loads(latest["schema"]), named_schemas=named_schemas)
    return latest["id"], parsed
# end::schema[]


# tag::encode[]
def encode(schema_id, parsed_schema, record):
    """Confluent wire format: magic byte, 4-byte big-endian schema ID, Avro body."""
    buf = io.BytesIO()
    buf.write(struct.pack(">bI", MAGIC_BYTE, schema_id))
    fastavro.schemaless_writer(buf, parsed_schema, record)
    return buf.getvalue()
# end::encode[]


def main():
    if DATASET not in DATASETS:
        print(f"unknown data set '{DATASET}' (seed or cutover)", file=sys.stderr)
        return 2
    print(f"Schema Registry: {SR_URL}")
    print(f"Kafka bootstrap: {BOOTSTRAP_SERVERS}")
    producer = Producer({"bootstrap.servers": BOOTSTRAP_SERVERS})
    delivered = []
    failed = []

    def on_delivery(err, msg):
        if err is not None:
            failed.append(f"{msg.topic()} {msg.key().decode()}: {err}")
        else:
            delivered.append((msg.topic(), msg.key().decode()))

    for topic, file, key_field in DATASETS[DATASET]:
        schema_id, parsed = load_schema(f"{topic}-value")
        with open(os.path.join(DATA_DIR, file)) as f:
            records = json.load(f)
        print(f"{topic}: {len(records)} record(s) encoded with schema ID {schema_id} ({topic}-value)")
        for record in records:
            producer.produce(topic=topic, key=record[key_field], value=encode(schema_id, parsed, record), callback=on_delivery)
    producer.flush(30)

    for topic, key in sorted(delivered):
        print(f"  delivered {topic} key={key}")
    for line in failed:
        print(f"  FAILED {line}", file=sys.stderr)
    print(f"{len(delivered)} record(s) delivered")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
