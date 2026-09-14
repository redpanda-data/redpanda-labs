# The application container. kafka-python is pinned: its protocol versions are
# the ones Envoy's Kafka broker filter parses, and newer clients negotiate
# request versions the filter does not rewrite.
FROM python:3.11-slim

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

WORKDIR /
