#!/bin/bash 

set -xeo pipefail

docker build -t transform-builder .
docker create --name extract transform-builder 
docker cp extract:/app/jq.wasm jq.wasm
docker rm extract

