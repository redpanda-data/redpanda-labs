#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR 1>/dev/null 2>/dev/null

source ../../config

echo On source cluster:
rpk --profile source registry subject list

echo On shadow cluster:
rpk --profile shadow registry subject list

popd 1>/dev/null 2>/dev/null
