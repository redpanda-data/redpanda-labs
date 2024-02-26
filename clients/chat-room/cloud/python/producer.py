from kafka import KafkaProducer
import json
class ChatProducer:
  def __init__(self, brokers, topic):
    self.topic = topic
    self.producer = KafkaProducer(
      bootstrap_servers=brokers,
      sasl_mechanism="SCRAM-SHA-256",
      security_protocol="SASL_SSL",
      sasl_plain_username="redpanda-chat-account",
      sasl_plain_password="<password>",
      value_serializer=lambda v: json.dumps(v).encode("utf-8"),
    )
  def send_message(self, user, message):
    self.producer.send(self.topic, {"user": user, "message": message})
    self.producer.flush()
  def close(self):
    self.producer.close()