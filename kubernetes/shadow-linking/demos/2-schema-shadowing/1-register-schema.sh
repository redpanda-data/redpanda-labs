#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR 1>/dev/null 2>/dev/null

# Register the schema
rpk --profile source registry schema create syslog-value --schema ./resources/syslog.avsc --type avro

popd 1>/dev/null 2>/dev/null
