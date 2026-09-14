import json

from kafka import KafkaProducer

from config import client_config


# tag::producer[]
class ChatProducer:
    def __init__(self, topic):
        self.topic = topic
        self.producer = KafkaProducer(
            value_serializer=lambda v: json.dumps(v).encode("utf-8"),
            **client_config(),
        )

    def send_message(self, user, message):
        """Produce one JSON-encoded chat message."""
        self.producer.send(self.topic, {"user": user, "message": message})
        self.producer.flush()
# end::producer[]

    def close(self):
        self.producer.close()
