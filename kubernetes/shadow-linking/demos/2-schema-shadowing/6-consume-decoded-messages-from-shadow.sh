#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR 1>/dev/null 2>/dev/null

source ../../config

rpk --profile shadow topic consume syslog -o0 -n1 --use-schema-registry -f'%v\n' | jq

popd 1>/dev/null 2>/dev/null
