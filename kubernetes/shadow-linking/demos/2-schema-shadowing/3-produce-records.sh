#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR 1>/dev/null 2>/dev/null

# Produce some records
cat ./resources/syslogs.json | rpk --profile source topic produce syslog --schema-id=topic

popd 1>/dev/null 2>/dev/null
