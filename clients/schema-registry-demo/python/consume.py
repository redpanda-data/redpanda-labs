#!/usr/bin/env python3
import os
import sys

from uuid import uuid4

from confluent_kafka import Consumer
from confluent_kafka.serialization import (
    SerializationContext, MessageField
)
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.error import SchemaRegistryError
from confluent_kafka.schema_registry.avro import AvroDeserializer
from confluent_kafka.schema_registry.protobuf import ProtobufDeserializer

from clickstream_key_pb2 import Key
from click import Click


USERNAME = os.environ.get("REDPANDA_SASL_USERNAME", "")
PASSWORD = os.environ.get("REDPANDA_SASL_PASSWORD", "")
SASL_MECH = os.environ.get("REDPANDA_SASL_MECHANISM", "SCRAM-SHA-256")
BOOTSTRAP = os.environ.get("REDPANDA_BROKERS", "localhost:9092")
SR_URL = os.environ.get("REDPANDA_SCHEMA_REGISTRY", "http://localhost:8081")
TOPIC = os.environ.get("REDPANDA_TOPIC", "clickstream")
TLS = os.environ.get("REDPANDA_TLS", "")


## Create a Schema Registry Client, configured for auth if needed.
sr_config = {"url": SR_URL}
if USERNAME and PASSWORD:
    sr_config.update({"basic.auth.user.info": f"{USERNAME}:{PASSWORD}"})
sr_client = SchemaRegistryClient(sr_config)

## Note: we don't need to fetch the protobuf schema for the key because it's
## effectively already defined in the clickstream_key_pb2.

## Retrieve our Value Schema. It should have been added via:
##  $ rpk registry schema create \
##    "${REDPANDA_TOPIC}-value" --schema clickstream-value.avsc
value_schema = None
try:
    value_schema = sr_client.get_latest_version(f"{TOPIC}-value")
except SchemaRegistryError as e:
    print(f"Failed to fetch schema '{TOPIC}-value': {e}", file=sys.stderr)
    print(f">> Did you run `rpk registry schema create ...`?", file=sys.stderr)
    sys.exit(1)

## Configure the Consumer with optional authentication & TLS settings.
config = {
    "bootstrap.servers": BOOTSTRAP,
    "auto.offset.reset": "earliest",
    "enable.auto.commit": True,
    "group.id": "kafka-python-example",
    "group.instance.id": f"kafka-python-example-{uuid4()}"
}
if USERNAME and PASSWORD:
    if TLS:
        config.update({"security.protocol": "SASL_SSL"})
    else:
        print(
            "warning: this configuration is unsupported by Redpanda", 
            file=sys.stderr
        )
        config.update({"security.protocol": "SASL_PLAIN"})
    config.update({
        "sasl.username": USERNAME,
        "sasl.password": PASSWORD,
        "sasl.mechanism": SASL_MECH,
    })
elif TLS:
    config.update({"security.protocol": "SSL"})
consumer = Consumer(config)

## Configure our Serializers.
key_deserializer = ProtobufDeserializer(Key, {"use.deprecated.format": False})
value_deserializer = AvroDeserializer(
    sr_client, value_schema.schema.schema_str, Click.from_dict
)

## Subscribe to our topic.
consumer.subscribe([TOPIC])

ticker = 0
while True:
    try:
        ticker += 1
        msg = consumer.poll(0.5) # poll aggressively to quickly catch ctrl-c
        if msg is None:
            if ticker == 10:
                print("...waiting for data", file=sys.stderr)
                ticker = 0
            continue
        key = key_deserializer(
            msg.key(),
            SerializationContext(msg.topic(), MessageField.KEY)
        )
        value = value_deserializer(
            msg.value(),
            SerializationContext(msg.topic(), MessageField.VALUE)
        )
        key_str = f"{{uuid: {key.uuid}, seq: {key.seq}}}"
        print(f"{msg.partition()}/{msg.offset()}: ({key_str}, {value})")

    except Exception as e:
        print(e, file=sys.stderr)
        break

## Be kind and say goodbye.
consumer.close()
