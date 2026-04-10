#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR 1>/dev/null 2>/dev/null

source ../../config

rpk --profile shadow topic consume syslog -o0 -n 1

popd 1>/dev/null 2>/dev/null
