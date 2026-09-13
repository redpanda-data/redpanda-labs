# The client container: the "application" of this migration. Python with the
# Confluent Kafka client, fastavro for hand-rolled Avro encoding, requests for
# the Schema Registry REST API, and curl + jq for the registration scripts.
FROM python:3.11-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl jq ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
WORKDIR /scripts
