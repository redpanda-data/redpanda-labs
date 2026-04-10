#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR 1>/dev/null 2>/dev/null

source ../../config

echo On source cluster:
rpk --profile source group describe consumer-group-foo

echo On shadow cluster:
rpk --profile shadow group describe consumer-group-foo

popd 1>/dev/null 2>/dev/null
