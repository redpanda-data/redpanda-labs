#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR 1>/dev/null 2>/dev/null

# Create a topic
rpk --profile source topic create syslog -p1 -r1

popd 1>/dev/null 2>/dev/null
