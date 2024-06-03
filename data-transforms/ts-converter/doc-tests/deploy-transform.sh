#!/bin/sh
rpk transform deploy --file ts-converter.wasm -i src -o sink --var "TIMESTAMP_TARGET_TYPE=string[%+]"
