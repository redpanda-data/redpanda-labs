#!/usr/bin/env python3
"""
Produce real, Avro-encoded topic data on the Confluent source, using the
schemas already registered in confluent-schema-registry (see
register-schemas.sh and register-complex-schemas.sh).

This writes to three topics, matching the Confluent default
TopicNameStrategy (topic name + "-value" = subject name):

  orders    -> orders-value      (simple Avro record)
  customers -> customers-value   (simple Avro record)
  shipping  -> shipping-value    (Avro record that REFERENCES address-value)

Records are encoded by hand with fastavro and framed in the standard
Confluent wire format (a 0x00 magic byte followed by a 4-byte big-endian
schema ID), rather than relying on confluent-kafka's built-in Avro
serializer. This makes the wire format explicit, since that format is
exactly what schema replication depends on being portable between
Confluent and Redpanda's Schema Registry implementations.

Run this AFTER scripts/register-schemas.sh and
scripts/register-complex-schemas.sh, so the subjects it depends on exist.
"""
import io
import json
import os
import struct
import sys

import fastavro
import requests
from confluent_kafka import Producer

SR_URL = os.environ.get("SR_URL", "http://confluent-schema-registry:8081")
BOOTSTRAP_SERVERS = os.environ.get("BOOTSTRAP_SERVERS", "confluent-kafka:29092")

MAGIC_BYTE = 0


def get_latest_version(subject):
    """Fetch the latest registered version of a subject."""
    resp = requests.get(f"{SR_URL}/subjects/{subject}/versions/latest", timeout=10)
    resp.raise_for_status()
    return resp.json()


def resolve_named_schema(subject, version, named_schemas):
    """Recursively parse a subject's schema (and any schemas it references)
    into fastavro's shared named_schemas registry, so referenced types like
    com.redpanda.demo.Address are resolvable when parsing the schema that
    references them."""
    resp = requests.get(f"{SR_URL}/subjects/{subject}/versions/{version}", timeout=10)
    resp.raise_for_status()
    data = resp.json()
    for ref in data.get("references", []):
        resolve_named_schema(ref["subject"], ref["version"], named_schemas)
    fastavro.parse_schema(json.loads(data["schema"]), named_schemas=named_schemas)


def load_schema(subject):
    """Fetch a subject's latest schema ID and a fully-resolved fastavro
    parsed schema (with any references inlined)."""
    latest = get_latest_version(subject)
    schema_id = latest["id"]
    named_schemas = {}
    for ref in latest.get("references", []):
        resolve_named_schema(ref["subject"], ref["version"], named_schemas)
    parsed = fastavro.parse_schema(json.loads(latest["schema"]), named_schemas=named_schemas)
    return schema_id, parsed


def encode(schema_id, parsed_schema, record):
    """Encode a record into the standard Confluent wire format:
    magic byte (0x00) + 4-byte big-endian schema ID + Avro binary body."""
    buf = io.BytesIO()
    buf.write(struct.pack(">bI", MAGIC_BYTE, schema_id))
    fastavro.schemaless_writer(buf, parsed_schema, record)
    return buf.getvalue()


def delivery_report(err, msg):
    if err is not None:
        print(f"  delivery failed for {msg.topic()}: {err}", file=sys.stderr)
    else:
        print(f"  delivered to {msg.topic()} [partition {msg.partition()}, offset {msg.offset()}]")


def main():
    producer = Producer({"bootstrap.servers": BOOTSTRAP_SERVERS})

    print("Loading schemas from the source Confluent Schema Registry...")
    orders_id, orders_schema = load_schema("orders-value")
    customers_id, customers_schema = load_schema("customers-value")
    shipping_id, shipping_schema = load_schema("shipping-value")
    print(f"  orders-value    -> schema ID {orders_id}")
    print(f"  customers-value -> schema ID {customers_id}")
    print(f"  shipping-value  -> schema ID {shipping_id} (references address-value)")
    print()

    orders = [
        {"order_id": "ord-1001", "amount": 42.50, "currency": "USD"},
        {"order_id": "ord-1002", "amount": 17.25, "currency": "USD"},
        {"order_id": "ord-1003", "amount": 99.99, "currency": "USD"},
    ]
    customers = [
        {"customer_id": "cust-500", "email": "alex@example.com"},
        {"customer_id": "cust-501", "email": "sam@example.com"},
    ]
    shipments = [
        {
            "order_id": "ord-1001",
            "destination": {
                "street": "1 Panda Way",
                "city": "San Francisco",
                "postal_code": "94105",
            },
        },
    ]

    print("Producing to 'orders'...")
    for order in orders:
        producer.produce(
            topic="orders",
            key=order["order_id"],
            value=encode(orders_id, orders_schema, order),
            callback=delivery_report,
        )

    print("Producing to 'customers'...")
    for customer in customers:
        producer.produce(
            topic="customers",
            key=customer["customer_id"],
            value=encode(customers_id, customers_schema, customer),
            callback=delivery_report,
        )

    print("Producing to 'shipping' (uses a schema reference)...")
    for shipment in shipments:
        producer.produce(
            topic="shipping",
            key=shipment["order_id"],
            value=encode(shipping_id, shipping_schema, shipment),
            callback=delivery_report,
        )

    producer.flush(10)
    print()
    print("Done. Run consume_topic_data.py to read these back.")


if __name__ == "__main__":
    main()
