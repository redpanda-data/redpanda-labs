#!/usr/bin/env python3
"""Produce or consume at a controlled rate/size, to see a client quota's real effect.

Usage:
  client.py produce --topic T --num-records N [--record-size-bytes N]
  client.py consume --topic T --group-id G --duration-sec N [--client-id ID]

TLS/SASL (unset by default - set these env vars to match an authenticated
cluster, e.g. SASL_SSL/SCRAM-SHA-512):
  KAFKA_BROKERS (default localhost:9092)
  KAFKA_SECURITY_PROTOCOL, KAFKA_SASL_MECHANISM, KAFKA_SASL_USERNAME,
  KAFKA_SASL_PASSWORD, KAFKA_SSL_CA_LOCATION, KAFKA_SSL_CHECK_HOSTNAME
"""
import argparse
import os
import time

from confluent_kafka import Consumer, Producer


def base_conf() -> dict:
    conf = {"bootstrap.servers": os.environ.get("KAFKA_BROKERS", "localhost:9092")}
    security_protocol = os.environ.get("KAFKA_SECURITY_PROTOCOL")
    if security_protocol:
        conf["security.protocol"] = security_protocol
    sasl_mechanism = os.environ.get("KAFKA_SASL_MECHANISM")
    if sasl_mechanism:
        conf["sasl.mechanisms"] = sasl_mechanism
    sasl_username = os.environ.get("KAFKA_SASL_USERNAME")
    if sasl_username:
        conf["sasl.username"] = sasl_username
    sasl_password = os.environ.get("KAFKA_SASL_PASSWORD")
    if sasl_password:
        conf["sasl.password"] = sasl_password
    ssl_ca_location = os.environ.get("KAFKA_SSL_CA_LOCATION")
    if ssl_ca_location:
        conf["ssl.ca.location"] = ssl_ca_location
    if os.environ.get("KAFKA_SSL_CHECK_HOSTNAME", "0") != "1":
        conf["ssl.endpoint.identification.algorithm"] = "none"
    return conf


def produce(topic: str, num_records: int, record_size_bytes: int, client_id: str | None,
            fetch_max_bytes: int | None, max_partition_fetch_bytes: int | None,
            batch_size_bytes: int | None) -> None:
    conf = base_conf()
    conf.update({"linger.ms": 5, "queue.buffering.max.kbytes": 2097151, "queue.buffering.max.messages": 1000000})
    if client_id:
        conf["client.id"] = client_id
    if batch_size_bytes:
        conf["batch.size"] = batch_size_bytes
    p = Producer(conf)
    payload = b"x" * record_size_bytes
    start = time.time()
    for i in range(num_records):
        while True:
            try:
                p.produce(topic, payload)
                break
            except BufferError:
                p.poll(0.1)
        if i % 10000 == 0:
            p.poll(0)
    p.flush(60)
    elapsed = time.time() - start
    total_bytes = num_records * record_size_bytes
    print(f"produced {num_records} records ({total_bytes:,} bytes) in {elapsed:.2f}s "
          f"({total_bytes / elapsed:,.0f} B/s, {num_records / elapsed:,.1f} records/sec)")


def consume(topic: str, group_id: str, duration_sec: float, client_id: str | None,
            fetch_max_bytes: int | None, max_partition_fetch_bytes: int | None) -> None:
    conf = base_conf()
    conf.update({"group.id": group_id, "auto.offset.reset": "earliest", "enable.auto.commit": False})
    if client_id:
        conf["client.id"] = client_id
    if fetch_max_bytes:
        conf["fetch.max.bytes"] = fetch_max_bytes
    if max_partition_fetch_bytes:
        conf["max.partition.fetch.bytes"] = max_partition_fetch_bytes
    c = Consumer(conf)
    c.subscribe([topic])

    start = time.time()
    total_bytes = msg_count = 0
    first_t = last_t = None
    while time.time() - start < duration_sec:
        msg = c.poll(1.0)
        if msg is None or msg.error():
            continue
        now = time.time()
        if first_t is None:
            first_t = now
        last_t = now
        total_bytes += len(msg.value())
        msg_count += 1
    c.close()

    # Active window (first message to last message), not the full wall-clock
    # duration - an unthrottled consumer can drain its backlog and go idle
    # well before duration_sec elapses, which would otherwise understate the
    # real rate.
    active_window = (last_t - first_t) if (first_t and last_t and last_t > first_t) else None
    rate = (total_bytes / active_window) if active_window else 0
    window_str = f"{active_window:.2f}" if active_window else "0"
    print(f"msgs={msg_count} bytes={total_bytes:,} active_window_s={window_str} "
          f"bytes_per_sec={rate:,.0f} records_per_sec={(msg_count / active_window) if active_window else 0:,.1f}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", required=True)

    pp = sub.add_parser("produce")
    pp.add_argument("--topic", required=True)
    pp.add_argument("--num-records", type=int, required=True)
    pp.add_argument("--record-size-bytes", type=int, default=1700)
    pp.add_argument("--client-id", default=None)
    pp.add_argument("--batch-size-bytes", type=int, default=None, help="producer batch.size, for the overshoot demo")

    pc = sub.add_parser("consume")
    pc.add_argument("--topic", required=True)
    pc.add_argument("--group-id", required=True)
    pc.add_argument("--duration-sec", type=float, required=True)
    pc.add_argument("--client-id", default=None)
    pc.add_argument("--fetch-max-bytes", type=int, default=None, help="consumer fetch.max.bytes, for the overshoot demo")
    pc.add_argument("--max-partition-fetch-bytes", type=int, default=None)

    args = p.parse_args()
    if args.command == "produce":
        produce(args.topic, args.num_records, args.record_size_bytes, args.client_id,
                 None, None, args.batch_size_bytes)
    else:
        consume(args.topic, args.group_id, args.duration_sec, args.client_id,
                 args.fetch_max_bytes, args.max_partition_fetch_bytes)


if __name__ == "__main__":
    main()
