import io
import argparse

from avro.io import BinaryDecoder, BinaryEncoder
from avro.io import DatumReader, DatumWriter
from avro.io import validate
from avro.schema import parse

from kafka import KafkaProducer
from kafka import KafkaConsumer
from pandaproxy_registry import SchemaRegistry

parser = argparse.ArgumentParser()
parser.add_argument('brokers', help='List of Redpanda brokers')
parser.add_argument('registry', help='Redpanda schema registry URI')
parser.add_argument('-t', '--topic', default='station-data', help='Name of topic')
args = parser.parse_args()

# Publish the schema
with open('data/weather.avsc') as f:
    schema = parse(f.read())

header = [field['name'] for field in schema.to_json()['fields']]
print(f'Header from schema: {header}')

print(f'Publishing schema to registry: {args.registry}')
registry = SchemaRegistry(args.registry)
id = registry.publish(schema.to_json())
print(f'Schema id: {id}')

# Send messages to Redpanda
with open('data/hurndata.txt') as f:
    data = f.readlines()[7:]

def as_avro(value):    
    writer = DatumWriter(schema)
    bytes_writer = io.BytesIO()
    encoder = BinaryEncoder(bytes_writer)
    writer.write(value, encoder)
    return bytes_writer.getvalue()

producer = KafkaProducer(
    bootstrap_servers = args.brokers,
    compression_type = 'gzip',
    value_serializer = as_avro
)

print(f'Sending {len(data)} messages to topic: {args.topic}...')
for record in data:
    fields = str(record).split()
    msg = dict(zip(header, fields))
    producer.send(args.topic, value=msg)
producer.flush()

# Retrieve the schema from the registry
print(f'Retrieving schema from registry: {args.registry}')
schema = parse(registry.get_schema(id))
print(schema)

def from_avro(value):
    bytes_reader = io.BytesIO(value)
    decoder = BinaryDecoder(bytes_reader)
    reader = DatumReader(schema)
    return reader.read(decoder)

consumer = KafkaConsumer(
    bootstrap_servers = args.brokers,
    group_id = 'weather-watchers',
    auto_offset_reset = 'earliest',
    value_deserializer = from_avro
)
consumer.subscribe(args.topic)

# Consume the messages and validate against the Avro schema
print(f'Consuming messages from topic: {args.topic}...')
while True:
    batch = consumer.poll(timeout_ms=1000)
    if not batch:
        break
    for tp, messages in batch.items():
        for msg in messages:
            print('[valid]' if validate(schema, msg.value) else '[invalid]', msg.value)
