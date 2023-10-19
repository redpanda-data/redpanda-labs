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
REDPANDA_BROKERS=<comma-separated list of brokers>
REDPANDA_TOPIC_NAME=test-topic

# Optional variables for connecting to a Redpanda Cloud environment:
# KAFKA_SECURITY_PROTOCOL=SASL_SSL
# KAFKA_SASL_MECHANISM=SCRAM-SHA-256
# REDPANDA_SERVICE_ACCOUNT=<service account name>
# REDPANDA_SERVICE_ACCOUNT_PASSWORD=<service account password>
```

## Provide `.csv` files to use as sample data

For example, Nasdaq's historical data downloads provide years of historical stock prices and volumes in `.csv` format: https://www.nasdaq.com/market-activity/quotes/historical.

## Run the producer and consumer

```shell
python producer.py
python consumer.py
```