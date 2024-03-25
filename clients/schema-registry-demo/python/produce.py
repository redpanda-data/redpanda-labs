#!/usr/bin/env python3
import os
import sys

from random import randrange
from uuid import uuid4

from confluent_kafka import Producer
from confluent_kafka.serialization import (
    SerializationContext, MessageField
)
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.error import SchemaRegistryError
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.schema_registry.protobuf import ProtobufSerializer

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

## Retrieve our Key Schema. It should have been added via:
##  $ rpk registry schema create \
##    "${REDPANDA_TOPIC}-value" --schema clickstream-key.proto
key_schema = None 
try:
    key_schema = sr_client.get_latest_version(f"{TOPIC}-key")
except SchemaRegistryError as e:
    print(f"Failed to fetch key schema '{TOPIC}-key': {e}", file=sys.stderr)
    print(f">> Did you run `rpk registry schema create ...`?", file=sys.stderr)
    sys.exit(1)

## Retrieve our Value Schema. It should have been added via:
##  $ rpk registry schema create \
##    "${REDPANDA_TOPIC}-value" --schema clickstream-value.avsc
value_schema = None
try:
    value_schema = sr_client.get_latest_version(f"{TOPIC}-value")
except SchemaRegistryError as e:
    print(f"Failed to fetch value schema '{TOPIC}-value': {e}",
          file=sys.stderr)
    print(f">> Did you run `rpk registry schema create` for {TOPIC}-value?",
          file=sys.stderr)
    sys.exit(1)

## Configure our Serializers.
key_serializer = ProtobufSerializer(
    Key, sr_client, {"use.deprecated.format": False}
)
value_serializer = AvroSerializer(
    sr_client, value_schema.schema.schema_str, Click.to_dict
)


## Configure the Producer with optional authentication & TLS settings.
config = {
    "bootstrap.servers": BOOTSTRAP,
    "linger.ms": 100,
    "batch.size": 1024 * 1024,
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
producer = Producer(config)

## Produce some sample data.
for i in range(0, 10_000):
    user_id = randrange(1, 101)

    key = Key(uuid=str(uuid4()), seq=i)
    value = Click(user_id, "navigation")

    producer.produce(
        topic=TOPIC,
        key=key_serializer(
            key,
            SerializationContext(TOPIC, MessageField.KEY)
        ),
        value=value_serializer(
            value,
            SerializationContext(TOPIC, MessageField.VALUE)
        ),
        on_delivery=lambda _e,m: print(
            f"produced {m.topic()}/{m.partition()} @ offset {m.offset()}"
        )
    )

## Be kind and flush.
producer.flush(30)
