#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR 1>/dev/null 2>/dev/null

source ../../config

rpk --profile shadow shadow failover shadow-link --all --no-confirm
sleep 5
rpk --profile shadow shadow status shadow-link

popd 1>/dev/null 2>/dev/null
