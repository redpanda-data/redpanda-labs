import pandas as pd
import random
import json
import time
from kafka import KafkaProducer

# Load the data
df = pd.read_csv('store_nyc.csv')

# Clean the data
df = df.dropna(subset=['lat'])
df['lat'] = pd.to_numeric(df['lat'], errors='coerce')

# Sort the data from north to south
df = df.sort_values('lat', ascending=False)

# Generate random cupcakes for each store
cupcakes = []
for _, row in df.iterrows():
    store = row['storeid']
    blueberry = random.randint(3, 10)
    strawberry = random.randint(3, 10)
    cupcakes.append({'store': str(store), 'blueberry': blueberry, 'strawberry': strawberry})

# Create a Kafka producer
producer = KafkaProducer(
  bootstrap_servers="co5heihkkm0vlrgadjt0.any.us-east-1.mpx.prd.cloud.redpanda.com:9092",
  security_protocol="SASL_SSL",
  sasl_mechanism="SCRAM-SHA-256",
  sasl_plain_username="admin",
  sasl_plain_password="1234qwer",
  value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

# Send the cupcakes data to Kafka
for cupcake in cupcakes:
    producer.send('inv-count', cupcake)
    producer.flush()
    time.sleep(0.5)  # pause for 2 seconds

for _ in range(60):
    store = random.randint(1, 90)
    cupcake = {'store': str(store), 'blueberry': 0, 'strawberry': 0}
    producer.send('inv-count', cupcake)
    producer.flush()
    time.sleep(2)  # pause for 4 seconds