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
REDPANDA_SERVICE_ACCOUNT=<service account name>
REDPANDA_SERVICE_ACCOUNT_PASSWORD=<service account password>
```

## Run the producer and consumer

```shell
python producer.py
python consumer.py
```