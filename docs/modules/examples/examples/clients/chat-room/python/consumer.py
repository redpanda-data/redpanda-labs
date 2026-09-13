import json
import uuid

from kafka import KafkaConsumer

from config import client_config


# tag::consumer[]
class ChatConsumer:
    """Joins a new consumer group each run and reads from the beginning of the
    topic, so every client sees the whole chat history."""

    def __init__(self, topic, group_id=None):
        self.consumer = KafkaConsumer(
            topic,
            group_id=group_id or str(uuid.uuid4()),
            auto_offset_reset="earliest",
            value_deserializer=lambda m: json.loads(m.decode("utf-8")),
            **client_config(),
        )

    def print_messages(self):
        for msg in self.consumer:
            print(f"{msg.value['user']}: {msg.value['message']}")
# end::consumer[]

    def close(self):
        self.consumer.close()
