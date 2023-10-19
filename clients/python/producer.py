import os
import csv
import glob
import logging
import pathlib

from dotenv import load_dotenv
from kafka import (KafkaAdminClient, KafkaProducer)
from kafka.admin import NewTopic
from kafka.errors import TopicAlreadyExistsError

load_dotenv()
logging.basicConfig(level=logging.INFO)

redpanda_cloud_brokers = os.getenv("REDPANDA_BROKERS")
kafka_security_protocol = os.getenv("KAFKA_SECURITY_PROTOCOL", "PLAINTEXT")
kafka_sasl_mechanism = os.getenv("KAFKA_SASL_MECHANISM", None)
redpanda_service_account = os.getenv("REDPANDA_SERVICE_ACCOUNT", None)
redpanda_service_account_password = os.getenv("REDPANDA_SERVICE_ACCOUNT_PASSWORD", None)
logging.info(f"Connecting to: {redpanda_cloud_brokers}")

#
# Create topic
#
topic_name = os.getenv("REDPANDA_TOPIC_NAME", "test-topic")
logging.info(f"Creating topic: {topic_name}")

admin = KafkaAdminClient(
    bootstrap_servers=redpanda_cloud_brokers,
    security_protocol=kafka_security_protocol,
    sasl_mechanism=kafka_sasl_mechanism,
    sasl_plain_username=redpanda_service_account,
    sasl_plain_password=redpanda_service_account_password,
    # ssl_cafile="ca.crt",
    # ssl_certfile="client.crt",
    # ssl_keyfile="client.key"
)
try:
    admin.create_topics(new_topics=[
        NewTopic(name=topic_name, num_partitions=1, replication_factor=1)])
except TopicAlreadyExistsError as e:
    logging.error(e)
finally:
    admin.close()

#
# Write to topic
#
logging.info(f"Writing to topic: {topic_name}")
producer = KafkaProducer(
    bootstrap_servers=redpanda_cloud_brokers,
    security_protocol=kafka_security_protocol,
    sasl_mechanism=kafka_sasl_mechanism,
    sasl_plain_username=redpanda_service_account,
    sasl_plain_password=redpanda_service_account_password,
    # ssl_cafile="ca.crt",
    # ssl_certfile="client.crt",
    # ssl_keyfile="client.key"
)

try:
    here = pathlib.Path(__file__).parent.resolve()
    for file in glob.glob(f"{here}/*.csv"):
        logging.info(f"Processing file: {file}")
        with open(file) as csvfile:
            reader = csv.reader(csvfile)
            next(reader, None)  # skip the header
            for row in reader:
                msg = ",".join(row)
                f = producer.send(topic_name, str.encode(msg))
                f.get(timeout=100)
                logging.info(f"Produced: {msg}")
except Exception as e:
    logging.error(e)
finally:
    producer.flush()
    producer.close()
