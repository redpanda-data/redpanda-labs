#!/usr/bin/env python3
"""Show what the client knows about the cluster behind Envoy.

  endpoint.py [--expect-routing source|shadow] [--routing-only] [--now]

The client has one address and it asks for topic metadata. Every broker
address that comes back is Envoy's own, because the Kafka broker filter
rewrote them, so nothing this client does can bypass the proxy. Which
cluster actually answered comes from Envoy's admin API, not from the client:
a Kafka client is not told, and does not need to know.
"""
import sys

import common


def main(argv):
    expect = argv[argv.index("--expect-routing") + 1] if "--expect-routing" in argv else None

    # --routing-only prints one line and skips the Kafka round trip, so that a
    # loop waiting for Envoy to change its mind does not wait for a client to
    # reconnect too, and so that the line does not change while an endpoint
    # goes from unhealthy to gone. --now answers with the current state
    # instead of waiting for Envoy to have a healthy endpoint, which is what
    # such a loop needs.
    routing_only = "--routing-only" in argv
    if not routing_only:
        print("bootstrap: %s" % common.BOOTSTRAP)
        partitions, brokers = common.broker_addresses()
        for line in brokers:
            print("broker %s" % line)
        print("topic %s has %d partition(s)" % (common.TOPIC, len(partitions)))

    report, routing = common.envoy_routing(0 if "--now" in argv else common.ENVOY_WAIT)
    if not routing_only:
        for priority, label, state in report:
            print("%s cluster (priority %d): %s" % (label, priority, state))
    if routing is None:
        common.die("Envoy has no healthy endpoint")
    print("Envoy is routing clients to the %s cluster" % routing)

    if expect is not None and routing != expect:
        common.die("expected Envoy to route to the %s cluster, it routes to %s" % (expect, routing))


if __name__ == "__main__":
    main(sys.argv[1:])
