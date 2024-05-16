#!/bin/sh
rpk transform deploy --file ts-converter.wasm --input src --output sink --var "TIMESTAMP_TARGET_TYPE=string[%+]"
