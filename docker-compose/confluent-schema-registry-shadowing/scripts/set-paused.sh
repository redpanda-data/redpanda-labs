#!/bin/bash
# Pause or resume Schema Registry replication on the shadow link without an
# interactive editor.
#
# `rpk shadow update` has no flags for individual fields: it opens the link's
# current configuration in $EDITOR and applies whatever you save. That is fine
# by hand, but it can't be scripted or tested. This script supplies a tiny
# non-interactive $EDITOR that sets the `paused` field for you.
#
# Usage:
#   ./scripts/set-paused.sh true    # pause replication, destination becomes writable
#   ./scripts/set-paused.sh false   # resume replication, write-block returns
set -e

PAUSED="${1:?usage: set-paused.sh <true|false>}"
LINK="${LINK:-confluent-schema-migration}"
CONTAINER="${CONTAINER:-redpanda-shadow}"
ADMIN="${ADMIN:-redpanda-shadow:9644}"

case "${PAUSED}" in
  true|false) ;;
  *) echo "error: argument must be 'true' or 'false', got '${PAUSED}'" >&2; exit 1 ;;
esac

# `paused` is omitted from the configuration when it is false, so the editor
# script sets an existing value if there is one and otherwise inserts the field
# under shadow_schema_registry_api.
docker exec "${CONTAINER}" sh -c "cat > /tmp/rpk-editor.sh <<'EDITOR'
#!/bin/sh
if grep -q '^ *paused:' \"\$1\"; then
  sed -i 's/^\\( *\\)paused: .*/\\1paused: ${PAUSED}/' \"\$1\"
else
  sed -i 's#^\\( *\\)source_url: \\(.*\\)#\\1source_url: \\2\\n\\1paused: ${PAUSED}#' \"\$1\"
fi
EDITOR
chmod +x /tmp/rpk-editor.sh"

docker exec -e EDITOR=/tmp/rpk-editor.sh "${CONTAINER}" \
  rpk shadow update "${LINK}" -X admin.hosts="${ADMIN}"

docker exec "${CONTAINER}" rpk shadow describe "${LINK}" \
  --print-registry -X admin.hosts="${ADMIN}" | grep -E "SHADOWING MODE|PAUSED"

echo "Schema Registry replication paused: ${PAUSED}"
