#!/usr/bin/env python3
"""Consume through Envoy as a consumer group, and record what happened.

  consume.py [--group <id>] [--no-commit] [--expect <n>] [--state <name>]

The group's committed offsets are read after it joins and before it commits
again, so the output says whether the group resumed from offsets that were
replicated to this cluster or started at the beginning of the topic.
"""
import sys
import time

import common
from kafka.structs import TopicPartition

JOIN_TIMEOUT = 30
IDLE_POLLS = 3


def main(argv):
    group = argv[argv.index("--group") + 1] if "--group" in argv else common.GROUP
    commit = "--no-commit" not in argv
    expect = int(argv[argv.index("--expect") + 1]) if "--expect" in argv else None
    state = argv[argv.index("--state") + 1] if "--state" in argv else None

    _, routing = common.envoy_routing()
    if routing is None:
        common.die("Envoy has no healthy cluster to send this client to")
    print("bootstrap: %s" % common.BOOTSTRAP)
    print("Envoy is routing clients to the %s cluster" % routing)

    client = common.consumer(group)
    keys = []
    start = {}
    end = {}
    try:
        client.subscribe([common.TOPIC])
        deadline = time.time() + JOIN_TIMEOUT
        while not client.assignment():
            keys.extend(_drain(client.poll(timeout_ms=1000)))
            if time.time() >= deadline:
                common.die("the group did not get an assignment within %ds" % JOIN_TIMEOUT)
        partitions = sorted(tp.partition for tp in client.assignment())
        for partition in partitions:
            start[partition] = client.committed(TopicPartition(common.TOPIC, partition))

        idle = 0
        while idle < IDLE_POLLS:
            batch = _drain(client.poll(timeout_ms=2000))
            if batch:
                keys.extend(batch)
                idle = 0
            else:
                idle += 1

        for partition in partitions:
            end[partition] = client.position(TopicPartition(common.TOPIC, partition))
        if commit and keys:
            client.commit()
    finally:
        client.close(autocommit=False)

    print("group %s read %d record(s) from %s" % (group, len(keys), common.TOPIC))
    if keys:
        print("keys %s to %s" % (min(keys), max(keys)))
    if any(offset is not None for offset in start.values()):
        print(
            "resumed from %s"
            % ", ".join(
                "partition %d at offset %s" % (p, start[p] if start[p] is not None else 0)
                for p in sorted(start)
            )
        )
    else:
        print("this group had no committed offsets here, so it started at the beginning of each partition")

    if state:
        common.write_state(
            state,
            {
                "bootstrap": common.BOOTSTRAP,
                "committed": commit and bool(keys),
                "end_offsets": end,
                "end_total": sum(end.values()),
                "envoy_routing": routing,
                "group": group,
                "keys": sorted(keys),
                "records": len(keys),
                "start_offsets": start,
                "topic": common.TOPIC,
            },
        )

    if expect is not None and len(keys) != expect:
        common.die("expected %d record(s), read %d" % (expect, len(keys)))


def _drain(batch):
    out = []
    for messages in batch.values():
        for message in messages:
            out.append(message.key.decode("utf-8"))
    return out


if __name__ == "__main__":
    main(sys.argv[1:])
