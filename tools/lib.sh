#!/usr/bin/env bash
# Shared definitions for the tools/ scripts. Source, do not execute.
#
# The slug rule and the reserved ids live here only; CONTRIBUTING.md and
# CLAUDE.md point at this file instead of repeating them.

# Lowercase letters, digits, hyphens; 1-64 chars; no leading or trailing hyphen.
SLUG_RE='^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$'

# Ids that can never be a solution slug or a step id:
#   progress, download, api   docs-site function paths under /solutions/
#   index                     the landing page stem
#   ROOT                      the component's own module
#   examples                  the ungated Product Docs code module
RESERVED_IDS="progress download api index ROOT examples"

valid_slug() { [[ "$1" =~ $SLUG_RE ]]; }

is_reserved() {
  local x
  for x in $RESERVED_IDS; do [ "$x" = "$1" ] && return 0; done
  return 1
}
