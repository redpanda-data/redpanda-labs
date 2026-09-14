#!/usr/bin/env python3
"""Read one value out of a fact the walkthrough recorded in /state.

  state.py <name> <key>[.<key>...]

scripts/verify.sh uses this so that the host needs no JSON tooling: every
assertion about an earlier point in the walkthrough reads its value from the
state file that step wrote. A missing file or key prints nothing and exits 1,
so the check that reads it fails rather than passing on an empty string.
"""
import json
import os
import sys

STATE_DIR = os.environ.get("STATE_DIR", "/state")


def main(argv):
    if len(argv) != 2:
        print("usage: state.py <name> <key>[.<key>...]", file=sys.stderr)
        return 2
    path = os.path.join(STATE_DIR, "%s.json" % argv[0])
    if not os.path.exists(path):
        print("%s does not exist; run the walkthrough first" % path, file=sys.stderr)
        return 1
    with open(path) as fh:
        value = json.load(fh)
    for key in argv[1].split("."):
        if isinstance(value, dict) and key in value:
            value = value[key]
        else:
            print("%s has no key %s" % (path, argv[1]), file=sys.stderr)
            return 1
    if isinstance(value, (dict, list)):
        print(json.dumps(value, sort_keys=True, separators=(",", ":")))
    else:
        print(value)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
