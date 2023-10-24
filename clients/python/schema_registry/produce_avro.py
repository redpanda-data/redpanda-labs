import os
import csv
import glob
import logging
import pathlib

from dotenv import load_dotenv
from kafka import KafkaAdminClient, KafkaProducer
from kafka.admin import NewTopic
from kafka.errors import TopicAlreadyExistsError
from registry import SchemaRegistry


load_dotenv()
logging.basicConfig(level=logging.INFO)

redpanda_brokers = os.getenv("REDPANDA_BROKERS")
redpanda_schema_registry = os.getenv("REDPANDA_SCHEMA_REGISTRY")
kafka_security_protocol = os.getenv("KAFKA_SECURITY_PROTOCOL", "PLAINTEXT")
kafka_sasl_mechanism = os.getenv("KAFKA_SASL_MECHANISM", None)
redpanda_username = os.getenv("REDPANDA_USERNAME", None)
redpanda_password = os.getenv("REDPANDA_PASSWORD", None)
logging.info("Connecting to: %s", redpanda_brokers)

#
# Register schema
#
json_schema = {
    "type": "record",
    "name": "simple",
    "namespace": "nasdaq.historical",
    "fields": [
        {"name": "date", "type": "string"},
        {"name": "last", "type": "string"},
        {"name": "volume", "type": "string"},
        {"name": "open", "type": "string"},
        {"name": "high", "type": "string"},
        {"name": "low", "type": "string"},
    ],
}

registry = SchemaRegistry(redpanda_schema_registry)
schema_id = registry.register(json_schema)

#
# Create topic
#
topic_name = os.getenv("REDPANDA_TOPIC_NAME", "nasdaq-historical-avro")
logging.info("Creating topic: %s", topic_name)

admin = KafkaAdminClient(
    bootstrap_servers=redpanda_brokers,
    security_protocol=kafka_security_protocol,
    sasl_mechanism=kafka_sasl_mechanism,
    sasl_plain_username=redpanda_username,
    sasl_plain_password=redpanda_password,
    # ssl_cafile="ca.crt",
    # ssl_certfile="client.crt",
    # ssl_keyfile="client.key"
)
try:
    admin.create_topics(
        new_topics=[NewTopic(name=topic_name, num_partitions=1, replication_factor=1)]
    )
except TopicAlreadyExistsError as e:
    logging.error(e)
finally:
    admin.close()

#
# Write to topic
#
logging.info("Writing to topic: %s", topic_name)
producer = KafkaProducer(
    bootstrap_servers=redpanda_brokers,
    security_protocol=kafka_security_protocol,
    sasl_mechanism=kafka_sasl_mechanism,
    sasl_plain_username=redpanda_username,
    sasl_plain_password=redpanda_password,
    # ssl_cafile="ca.crt",
    # ssl_certfile="client.crt",
    # ssl_keyfile="client.key"
)


def parse(stock):
    """Parse CSV formatted stock."""
    if isinstance(stock, list):
        if len(stock) == 6:
            return {
                "date": stock[0],
                "last": stock[1],
                "volume": stock[2],
                "open": stock[3],
                "high": stock[4],
                "low": stock[5],
            }
    return {}


# Fetch schema
parsed_schema = registry.fetch(schema_id)

here = pathlib.Path(__file__).parent.resolve()
for file in glob.glob(f"{here}/../../data/*.csv"):
    logging.info("Processing file: %s", file)
    with open(file, encoding="utf-8") as csvfile:
        reader = csv.reader(csvfile)
        next(reader, None)  # skip the header
        for row in reader:
            msg = parse(row)
            msg_avro = SchemaRegistry.encode(msg, parsed_schema, schema_id)
            f = producer.send(topic_name, msg_avro)
            f.get(timeout=100)
            logging.info("Produced: %s", msg_avro)

producer.flush()
producer.close()
