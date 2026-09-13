#!/usr/bin/env bash
# Pause or resume Schema Registry replication on the shadow link without an
# interactive editor.
#
# `rpk shadow update` has no flags for individual fields: it opens the link's
# configuration in $EDITOR and applies what you save. That works by hand and
# cannot be scripted, so this script hands rpk a tiny non-interactive editor
# that sets `paused` under shadow_schema_registry_api. It runs inside the rpk
# helper container (`make pause`, `make resume`).
#
#   set-paused.sh true    pause: the destination contexts become writable
#   set-paused.sh false   resume: the write block returns
set -euo pipefail

PAUSED="${1:?usage: set-paused.sh <true|false>}"
LINK="${SHADOW_LINK:-schema-registry-migration}"

case "$PAUSED" in
  true|false) ;;
  *) echo "set-paused: argument must be true or false, got '$PAUSED'" >&2; exit 1 ;;
esac

# tag::editor[]
# `paused` is absent from the configuration while it is false, so the editor
# replaces the line when it exists and otherwise inserts it after source_url,
# the first line of the shadow_schema_registry_api block.
editor=$(mktemp)
cat > "$editor" <<EDITOR
#!/bin/sh
if grep -q '^ *paused:' "\$1"; then
  sed -i 's/^\\( *\\)paused: .*/\\1paused: ${PAUSED}/' "\$1"
else
  sed -i 's#^\\( *\\)source_url: \\(.*\\)#\\1source_url: \\2\\n\\1paused: ${PAUSED}#' "\$1"
fi
EDITOR
chmod +x "$editor"

EDITOR="$editor" rpk shadow update "$LINK"
# end::editor[]

rpk shadow describe "$LINK" --print-registry | grep -E 'SHADOWING MODE|PAUSED'
echo "Schema Registry replication paused: $PAUSED"
