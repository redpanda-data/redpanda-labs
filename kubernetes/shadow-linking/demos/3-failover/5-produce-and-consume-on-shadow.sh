#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR 1>/dev/null 2>/dev/null

# Produce some records to the shadow
seq 3 5 | rpk --profile shadow topic produce foo

# Consume the shadow cluster for 10 seconds
timeout 10s rpk --profile shadow topic consume foo -g consumer-group-foo || true

popd 1>/dev/null 2>/dev/null
