#!/usr/bin/env bash
# Print a JSON array of solution slugs for a CI matrix.
#
#   tools/changed-solutions.sh [<base-ref>]   slugs touched since <base-ref> (default origin/main)
#   tools/changed-solutions.sh --all          every slug under solutions/
#
# A slug is "touched" when git diff --name-only <base>...HEAD lists a path
# under solutions/<slug>/ or docs/modules/<slug>/. docs/modules/ROOT and
# docs/modules/examples are not solutions and are skipped. Only slugs that
# still exist as solutions/<slug>/ at HEAD are printed, so a deleted solution
# never lands in the matrix. Output is always valid JSON, [] when nothing matches.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

all_slugs() {
  [ -d solutions ] || return 0
  find solutions -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}

to_json() {
  # stdin: one slug per line
  local first=1
  printf '['
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    if [ $first -eq 1 ]; then first=0; else printf ','; fi
    printf '"%s"' "$s"
  done
  printf ']\n'
}

if [ "${1:-}" = "--all" ]; then
  all_slugs | to_json
  exit 0
fi

base=${1:-origin/main}
if ! git rev-parse --verify --quiet "$base" >/dev/null; then
  echo "changed-solutions: unknown base ref '$base'" >&2
  exit 2
fi

git diff --name-only "$base...HEAD" \
  | sed -nE 's#^(solutions|docs/modules)/([^/]+)/.*#\2#p' \
  | sort -u \
  | while IFS= read -r slug; do
      case "$slug" in ROOT|examples) continue ;; esac
      [ -d "solutions/$slug" ] && echo "$slug"
    done \
  | to_json
