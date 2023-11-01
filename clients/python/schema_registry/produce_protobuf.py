import os
import csv
import glob
import logging
import stock_pb2

from dotenv import load_dotenv
from confluent_kafka import Producer
from confluent_kafka.admin import AdminClient, NewTopic, KafkaException
from confluent_kafka.serialization import (
    SerializationContext,
    MessageField,
)
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.protobuf import ProtobufSerializer

load_dotenv()
logging.basicConfig(level=logging.INFO)

redpanda_brokers = os.getenv("REDPANDA_BROKERS")
redpanda_schema_registry = os.getenv("REDPANDA_SCHEMA_REGISTRY")
kafka_security_protocol = os.getenv("KAFKA_SECURITY_PROTOCOL", "PLAINTEXT")
kafka_sasl_mechanism = os.getenv("KAFKA_SASL_MECHANISM", None)
redpanda_username = os.getenv("REDPANDA_USERNAME", None)
redpanda_password = os.getenv("REDPANDA_PASSWORD", None)
logging.info("Connecting to: %s", redpanda_brokers)

conf = {"bootstrap.servers": redpanda_brokers}
if kafka_security_protocol and "SASL" in kafka_security_protocol:
    conf.update(
        {
            "security.protocol": kafka_security_protocol,
            "sasl_mechanism": kafka_sasl_mechanism,
            "sasl_plain_username": redpanda_username,
            "sasl_plain_password": redpanda_password,
            # "ssl_cafile": "ca.crt",
            # "ssl_certfile": "client.crt",
            # "ssl_keyfile": "client.key"
        }
    )


# pylint: disable=E1101
def csv_to_stock(r):
    """Parse CSV formatted stock."""
    parts = r.split(",")
    return stock_pb2.Stock(
        date=parts[0],
        last=parts[1],
        volume=parts[2],
        open=parts[3],
        high=parts[4],
        low=parts[5],
    )


registry = SchemaRegistryClient({"url": redpanda_schema_registry})
protobuf_serializer = ProtobufSerializer(
    stock_pb2.Stock, registry, {"use.deprecated.format": False}
)

#
# Create topic
#
topic_name = os.getenv("REDPANDA_TOPIC_NAME", "stock-proto")
logging.info("Creating topic: %s", topic_name)

admin = AdminClient(conf)
try:
    topic = NewTopic(topic=topic_name, num_partitions=1, replication_factor=1)
    admin.create_topics([topic])
except KafkaException as e:
    logging.error(e)


#
# Write to topic
#
def delivery_report(err, msg):
    """Logs the success or failure of message delivery."""
    if err is not None:
        logging.error("Unable to deliver message: %s", err)
    else:
        out = f"topic: {msg.topic()}, "
        out += f"partition: {msg.partition()}, "
        out += f"offset: {msg.offset()}, "
        out += f"value: {msg.value()}"
        logging.info(out)


logging.info("Writing to topic: %s", topic_name)
producer = Producer(conf)

here = os.path.realpath(os.path.dirname(__file__))
for file in glob.glob(f"{here}/../../data/*.csv"):
    logging.info("Processing file: %s", file)
    with open(file, encoding="utf-8") as f:
        reader = csv.reader(f)
        next(reader, None)  # skip the header
        for row in reader:
            stock = csv_to_stock(",".join(row))
            producer.produce(
                topic=topic_name,
                value=protobuf_serializer(
                    stock, SerializationContext(topic_name, MessageField.VALUE)
                ),
                on_delivery=delivery_report,
            )

producer.flush()
