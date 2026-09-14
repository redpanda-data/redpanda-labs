#!/usr/bin/env python3
"""Compare the two clusters partition by partition, and wait until they agree.

  parity.py [--expect <n>] [--state <name>] [--timeout <seconds>]

This is the only client script that reaches each cluster directly: a proxy
that hides which cluster answered cannot be used to compare them. Nothing is
asserted about lag reported by the link; the check is the data itself, so
`ok` here means the shadow cluster holds every record the source holds.
"""
import sys
import time

import common


def main(argv):
    expect = int(argv[argv.index("--expect") + 1]) if "--expect" in argv else None
    state = argv[argv.index("--state") + 1] if "--state" in argv else None
    timeout = int(argv[argv.index("--timeout") + 1]) if "--timeout" in argv else 120

    deadline = time.time() + timeout
    source = shadow = None
    while True:
        source = common.watermarks(common.SOURCE_BOOTSTRAP, common.TOPIC)
        shadow = common.watermarks(common.SHADOW_BOOTSTRAP, common.TOPIC)
        at_parity = bool(source) and source == shadow
        enough = expect is None or common.total(source) == expect
        if at_parity and enough:
            break
        if time.time() >= deadline:
            print("source: %s" % source, file=sys.stderr)
            print("shadow: %s" % shadow, file=sys.stderr)
            common.die("the clusters did not reach parity within %ds" % timeout)
        time.sleep(3)

    print("topic: %s" % common.TOPIC)
    for partition in sorted(source):
        print(
            "partition %d: source %d, shadow %d"
            % (partition, source[partition], shadow[partition])
        )
    print(
        "source holds %d record(s), shadow holds %d: the clusters are at parity"
        % (common.total(source), common.total(shadow))
    )

    if state:
        common.write_state(
            state,
            {
                "partitions": sorted(source),
                "shadow_total": common.total(shadow),
                "shadow_watermarks": shadow,
                "source_total": common.total(source),
                "source_watermarks": source,
                "topic": common.TOPIC,
            },
        )


if __name__ == "__main__":
    main(sys.argv[1:])
