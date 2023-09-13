
import json
from confluent_kafka import KafkaException
from confluent_kafka.avro import AvroConsumer
from confluent_kafka import avro 

def consume():
    config = {
        "bootstrap.servers": "localhost:9092",
        "schema.registry.url": "http://localhost:8081",
        "group.id": "my-connsumer1",
        "auto.offset.reset": "earliest"
    }

    consumer = AvroConsumer(config)
    consumer.subscribe(["test_avro"])

    while True:
      try:
        msg = consumer.poll(1)

        if msg is None:
          continue

        print("Key is :" + json.dumps(msg.key()))
        print("Value is :" + json.dumps(msg.value()))
        print("-------------------------")

      except KafkaException as e:
        print('Kafka failure ' + e)

    consumer.close()

def main():
    consume()

if __name__ == '__main__':
    main()