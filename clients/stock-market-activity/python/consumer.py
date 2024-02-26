import os
import logging
from dotenv import load_dotenv
from confluent_kafka import Consumer

load_dotenv()
logging.basicConfig(level=logging.INFO)

redpanda_brokers = os.getenv("REDPANDA_BROKERS")
kafka_security_protocol = os.getenv("KAFKA_SECURITY_PROTOCOL", "PLAINTEXT")
kafka_sasl_mechanism = os.getenv("KAFKA_SASL_MECHANISM", None)
redpanda_username = os.getenv("REDPANDA_USERNAME", None)
redpanda_password = os.getenv("REDPANDA_PASSWORD", None)
logging.info("Connecting to: %s", redpanda_brokers)

conf = {
    "bootstrap.servers": redpanda_brokers,
    "group.id": "redpanda-labs",
    "auto.offset.reset": "earliest",
}
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


#
# Read from topic
#
def reset_offset(consumer, partitions):
    """Reset consumer offsets to zero."""
    for p in partitions:
        p.offset = 0
    consumer.assign(partitions)
    logging.info("Consumer assignments: %s", partitions)


topic_name = os.getenv("REDPANDA_TOPIC_NAME", "test-topic")
c = Consumer(conf)
c.subscribe([topic_name], on_assign=reset_offset)

while True:
    try:
        msg = c.poll(timeout=1.0)
        if msg is None:
            continue
        if msg.error():
            logging.error(msg.error())
        else:
            out = f"topic: {msg.topic()}, "
            out += f"partition: {msg.partition()}, "
            out += f"offset: {msg.offset()}, "
            out += f"value: {msg.value()}"
            logging.info(out)
    except KeyboardInterrupt:
        break

c.close()
