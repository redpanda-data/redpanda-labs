#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR 1>/dev/null 2>/dev/null

# Produce a record
echo "Hello, world" | rpk --profile source topic produce basic

popd 1>/dev/null 2>/dev/null
