# Redpanda Python Examples

## Create Python virtual environment

```shell
python3 -m venv env
source env/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

## Create dotenv file

```shell
vim .env
REDPANDA_BROKERS=localhost:9092
REDPANDA_SCHEMA_REGISTRY=http://localhost:8081
# REDPANDA_TOPIC_NAME=<optional alternate topic name>

# Optional variables for connecting to a Redpanda Cloud environment:
# KAFKA_SECURITY_PROTOCOL=SASL_SSL
# KAFKA_SASL_MECHANISM=SCRAM-SHA-256
# REDPANDA_USERNAME=<service account username>
# REDPANDA_PASSWORD=<service account password>
```

## Run the CSV producer and consumer

```shell
python producer.py
python consumer.py
```

## Run the Avro producer and consumer

```shell
python schema_registry/produce_avro.py
python schema_registry/consume_avro.py
```
