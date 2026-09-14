#!/usr/bin/env python3
"""Shared helpers for the client scripts.

The application scripts are given one bootstrap server, the Envoy address in
BOOTSTRAP_SERVERS, and never name a cluster: that is the point of the proxy.
parity.py and offsets.py are the exceptions. They compare the two clusters,
so they reach each of them directly.

Facts that only hold at one point in the walkthrough (the watermarks before
the disaster, the offsets the link replicated, the records read while the
source was down) are written to /state as JSON. scripts/verify.sh asserts
them at the end, when the source cluster is already gone.
"""
import json
import os
import sys
import time
import urllib.request

from kafka import KafkaConsumer, KafkaProducer
from kafka.errors import NoBrokersAvailable
from kafka.structs import TopicPartition

BOOTSTRAP = os.environ.get("BOOTSTRAP_SERVERS", "envoy:9092")
SOURCE_BOOTSTRAP = os.environ.get("SOURCE_BOOTSTRAP_SERVERS", "redpanda-source:9092")
SHADOW_BOOTSTRAP = os.environ.get("SHADOW_BOOTSTRAP_SERVERS", "redpanda-shadow:9092")
ENVOY_ADMIN = os.environ.get("ENVOY_ADMIN_URL", "http://envoy:9901")
TOPIC = os.environ.get("DR_TOPIC", "dr-orders")
GROUP = os.environ.get("DR_GROUP", "dr-consumers")
STATE_DIR = os.environ.get("STATE_DIR", "/state")

# kafka-python only ever sends Metadata v1, and Envoy's Kafka broker filter
# parses and rewrites that response. Pinning the version keeps the client off
# the version-probing path, which the filter closes the connection on.
API_VERSION = (2, 5, 0)

# Envoy needs a few seconds to notice that a cluster changed state, and a
# client that reconnects during a failover sees the connection refused first.
# Retrying is what a production client does too, so the scripts do it here
# instead of pretending the first attempt always works.
CONNECT_ATTEMPTS = 10
CONNECT_DELAY = 3
METADATA_TIMEOUT = 30
# Envoy marks an endpoint healthy only after two consecutive successful health
# checks, so for the first seconds after `make up` it has nowhere to send
# traffic and a client that connects gets no metadata back. On a loaded
# machine that can take a minute or two, so every script waits it out and
# `make up` does not return until Envoy has an endpoint.
ENVOY_WAIT = 240


def die(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def read_records(path):
    """The records to produce, from a committed JSON array."""
    with open(path) as fh:
        records = json.load(fh)
    if not isinstance(records, list) or not records:
        die("%s must hold a non-empty JSON array" % path)
    return records


def write_state(name, data):
    os.makedirs(STATE_DIR, exist_ok=True)
    path = os.path.join(STATE_DIR, "%s.json" % name)
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return path


def _connect(servers, factory):
    last = None
    for attempt in range(CONNECT_ATTEMPTS):
        try:
            return factory()
        except NoBrokersAvailable as err:
            last = err
            if attempt < CONNECT_ATTEMPTS - 1:
                time.sleep(CONNECT_DELAY)
    die("no broker answered %s after %d attempts: %s" % (servers, CONNECT_ATTEMPTS, last))


def producer(bootstrap=None):
    servers = bootstrap or BOOTSTRAP
    return _connect(
        servers,
        lambda: KafkaProducer(
            bootstrap_servers=[servers],
            key_serializer=lambda k: k.encode("utf-8"),
            value_serializer=lambda v: json.dumps(v, sort_keys=True).encode("utf-8"),
            acks="all",
            # No retries on purpose: a write that needs one is a write this
            # walkthrough wants to see fail, and a silent retry can duplicate
            # a record, which would make the counts wrong.
            retries=0,
            request_timeout_ms=20000,
            api_version=API_VERSION,
        ),
    )


def consumer(group, bootstrap=None, idle_ms=8000):
    servers = bootstrap or BOOTSTRAP
    return _connect(
        servers,
        lambda: KafkaConsumer(
            bootstrap_servers=[servers],
            group_id=group,
            auto_offset_reset="earliest",
            enable_auto_commit=False,
            consumer_timeout_ms=idle_ms,
            request_timeout_ms=20000,
            api_version=API_VERSION,
        ),
    )


# Envoy's endpoint priorities, in the order envoy/envoy.yaml declares them.
PRIORITIES = ((0, "source"), (1, "shadow"))


def envoy_routing(wait_seconds=ENVOY_WAIT):
    """The cluster Envoy is sending Kafka traffic to, from Envoy's own view.

    Priority 0 is the source cluster and priority 1 is the shadow cluster, so
    Envoy picks the healthy endpoint at the lowest priority. A cluster that
    stopped answering reports `unhealthy`, and one whose container is gone
    leaves the endpoint list altogether, so both states are reported.
    """
    deadline = time.time() + wait_seconds
    while True:
        report, routing = _envoy_routing()
        if routing is not None or time.time() >= deadline:
            return report, routing
        time.sleep(2)


def _envoy_routing():
    with urllib.request.urlopen("%s/clusters?format=json" % ENVOY_ADMIN, timeout=10) as response:
        status = json.load(response)
    found = {}
    for cluster in status.get("cluster_statuses", []):
        if cluster.get("name") != "redpanda":
            continue
        for host in cluster.get("host_statuses", []):
            health = host.get("health_status", {})
            healthy = not health.get("failed_active_health_check", False) and health.get(
                "eds_health_status"
            ) != "UNHEALTHY"
            priority = host.get("priority", 0)
            found[priority] = found.get(priority, False) or healthy
    report = [
        (priority, label, "healthy" if found.get(priority) else ("unhealthy" if priority in found else "no endpoint"))
        for priority, label in PRIORITIES
    ]
    return report, next((label for _, label, state in report if state == "healthy"), None)


def broker_addresses(bootstrap=None):
    """The broker addresses the client is told to use, after Envoy rewrote them."""
    client = consumer(None, bootstrap=bootstrap)
    try:
        partitions = _partitions(client, TOPIC)
        brokers = client._client.cluster.brokers()
        return partitions, sorted(
            "%s at %s:%s" % (b.nodeId, b.host, b.port) for b in brokers if b.nodeId != "bootstrap-0"
        )
    finally:
        client.close()


def _partitions(client, topic):
    """Wait until the client has metadata for the topic, then list its partitions.

    Assigning a partition is what puts the topic into the client's metadata
    set; `partitions_for_topic` alone never asks for it.
    """
    client.assign([TopicPartition(topic, 0)])
    deadline = time.time() + METADATA_TIMEOUT
    while True:
        partitions = client.partitions_for_topic(topic)
        if partitions:
            return sorted(partitions)
        if time.time() >= deadline:
            die("no metadata for %s after %ds" % (topic, METADATA_TIMEOUT))
        client.poll(timeout_ms=500)


def watermarks(bootstrap, topic):
    """High watermark per partition, read straight from one cluster."""
    client = consumer(None, bootstrap=bootstrap)
    try:
        partitions = _partitions(client, topic)
        tps = [TopicPartition(topic, p) for p in partitions]
        client.assign(tps)
        ends = client.end_offsets(tps)
        return {tp.partition: ends[tp] for tp in tps}
    finally:
        client.close()


def committed_offsets(bootstrap, topic, group):
    """Committed offset per partition for one group, read from one cluster.

    The partitions are assigned, not subscribed, so reading the offsets never
    joins the group and never triggers a rebalance.
    """
    client = consumer(group, bootstrap=bootstrap)
    try:
        partitions = _partitions(client, topic)
        tps = [TopicPartition(topic, p) for p in partitions]
        client.assign(tps)
        out = {}
        for tp in tps:
            offset = client.committed(tp)
            if offset is not None:
                out[tp.partition] = offset
        return out or None
    finally:
        client.close()


def total(offsets):
    return sum(offsets.values()) if offsets else 0
