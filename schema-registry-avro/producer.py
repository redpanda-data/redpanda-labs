
import json
from uuid import uuid4
from confluent_kafka import KafkaException
from confluent_kafka.avro import AvroProducer 
from confluent_kafka import avro

def delivery_callback(error, message):
    if error:
        print("Failed to send the message: %s" % error)
    else:
        print(f"Message with the key {message.key()} has been produced to the topic {message.topic()}")

def load_avro_schema_from_file():
    key_schema_string = """
    {"type": "string"}
    """

    key_schema = avro.loads(key_schema_string)
    value_schema = avro.load('./schemas/click_event.avsc')

    return key_schema, value_schema

def produce():
    config = {
        'bootstrap.servers' : "localhost:9092",
        'schema.registry.url' : "http://localhost:8081"
    }

    key_schema, value_schema = load_avro_schema_from_file()
    
    producer = AvroProducer(
        config,
        default_key_schema = key_schema,
        default_value_schema = value_schema
    )

    try:
        key = str(uuid4())
        value_str = '{"user_id":2,"event_type":"CLICK","ts":"2021-12-12"}'
        value = json.loads(value_str) 

        producer.produce(
            topic = "clickstream",
            key = key,
            value = value,
            on_delivery = delivery_callback
        )

        producer.poll(10000)
        producer.flush()
    
    except KafkaException as e:
        print("Error occurred during message production:", e)
    
    print("Done!")

def main():
    produce()

if __name__ == "__main__":
    main()
