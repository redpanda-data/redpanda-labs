#!/bin/sh

# Create a temporary schema file since RPK needs one.
SCHEMA_FILE=$(mktemp "epoch.XXXXXXXXXX.avsc")
function cleanup {
    rm "${SCHEMA_FILE}"
}
trap cleanup EXIT

echo '{"type": "long", "name": "epoch"}' > "${SCHEMA_FILE}"
rpk registry schema create \
    src-value --schema "${SCHEMA_FILE}"