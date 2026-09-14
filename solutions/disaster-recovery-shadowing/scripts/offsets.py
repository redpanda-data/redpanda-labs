#!/usr/bin/env python3
"""Wait until the consumer group's committed offsets reach the shadow cluster.

  offsets.py [--group <id>] [--state <name>] [--timeout <seconds>]

Topic data and consumer offsets are replicated by two different tasks of the
same link, so they arrive independently. This reads the group's committed
offsets from each cluster directly and waits until they match, which is the
thing that lets a consumer resume instead of reprocessing after a failover.
"""
import sys
import time

import common


def main(argv):
    group = argv[argv.index("--group") + 1] if "--group" in argv else common.GROUP
    state = argv[argv.index("--state") + 1] if "--state" in argv else None
    timeout = int(argv[argv.index("--timeout") + 1]) if "--timeout" in argv else 120

    deadline = time.time() + timeout
    source = shadow = None
    while True:
        source = common.committed_offsets(common.SOURCE_BOOTSTRAP, common.TOPIC, group)
        shadow = common.committed_offsets(common.SHADOW_BOOTSTRAP, common.TOPIC, group)
        if source and source == shadow:
            break
        if time.time() >= deadline:
            print("source: %s" % source, file=sys.stderr)
            print("shadow: %s" % shadow, file=sys.stderr)
            common.die("the group's offsets did not reach the shadow cluster within %ds" % timeout)
        time.sleep(3)

    print("group: %s" % group)
    for partition in sorted(source):
        print(
            "partition %d: source offset %d, shadow offset %d"
            % (partition, source[partition], shadow[partition])
        )
    print("the shadow cluster holds the same committed offsets as the source")

    if state:
        common.write_state(
            state,
            {
                "group": group,
                "shadow_offsets": shadow,
                "shadow_total": common.total(shadow),
                "source_offsets": source,
                "source_total": common.total(source),
                "topic": common.TOPIC,
            },
        )


if __name__ == "__main__":
    main(sys.argv[1:])
