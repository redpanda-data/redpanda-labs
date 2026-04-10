#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR 1>/dev/null 2>/dev/null

# Produce some records to the source
seq 0 2 | rpk --profile source topic produce foo

# Consume the source cluster for 10 seconds
timeout 10s rpk --profile source topic consume foo -g consumer-group-foo || true

popd 1>/dev/null 2>/dev/null
