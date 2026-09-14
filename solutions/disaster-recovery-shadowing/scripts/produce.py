#!/usr/bin/env python3
"""Produce the committed sample records through Envoy.

  produce.py <sample-data file> [--expect-rejected] [--state <name>]

The bootstrap server is always BOOTSTRAP_SERVERS, the Envoy address, before,
during, and after the failover. With --expect-rejected the script asserts the
opposite of a successful write: that the cluster refused it, which is what a
shadow topic does until you fail the link over.
"""
import sys

from kafka.errors import KafkaError

import common


def main(argv):
    if not argv or argv[0].startswith("--"):
        common.die("usage: produce.py <sample-data file> [--expect-rejected] [--state <name>]")
    path = argv[0]
    expect_rejected = "--expect-rejected" in argv
    state = argv[argv.index("--state") + 1] if "--state" in argv else None

    records = common.read_records(path)
    _, routing = common.envoy_routing()
    if routing is None:
        common.die("Envoy has no healthy cluster to send this client to")
    print("bootstrap: %s" % common.BOOTSTRAP)
    print("Envoy is routing clients to the %s cluster" % routing)

    client = common.producer()
    sent = 0
    refusal = None
    try:
        for record in records:
            try:
                client.send(common.TOPIC, key=record["order_id"], value=record).get(timeout=20)
                sent += 1
            except KafkaError as err:
                refusal = type(err).__name__
                break
    finally:
        client.close(timeout=10)

    if expect_rejected:
        if refusal is None:
            common.die("the write to %s succeeded, but a shadow topic should refuse it" % common.TOPIC)
        print("the write to %s was refused: %s" % (common.TOPIC, refusal))
        print("a shadow topic is read-only until the link is failed over")
    else:
        if refusal is not None:
            common.die("the write to %s failed after %d record(s): %s" % (common.TOPIC, sent, refusal))
        print("produced %d record(s) to %s" % (sent, common.TOPIC))
        print("keys %s to %s" % (records[0]["order_id"], records[-1]["order_id"]))

    if state:
        common.write_state(
            state,
            {
                "bootstrap": common.BOOTSTRAP,
                "envoy_routing": routing,
                "keys": [r["order_id"] for r in records[:sent]],
                "produced": sent,
                "refused": refusal,
                "topic": common.TOPIC,
            },
        )


if __name__ == "__main__":
    main(sys.argv[1:])
