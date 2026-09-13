#!/usr/bin/env bash
# Capture the expected output of every command block of a solution.
#
#   tools/capture-expected.sh <slug>
#
# Run it on a fresh stack (`make clean && make up` in solutions/<slug>/), the
# same state the Doc Detective run starts from. It walks the steps in
# :page-solution-steps: order, runs every runnable command block of every
# step page exactly as tools/gen-dd-specs.mjs would (bash, set -euo pipefail,
# .env loaded, cwd = the solution directory), and writes each command's
# stdout to solutions/<slug>/steps/<step-id>/expected/<tag>.txt. Outputs are
# captured, never typed; after a change in behaviour, run this and review the
# diff. A command whose stdout is empty gets no file unless a page already
# includes one. Commands marked [.manual] on the page are skipped.
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
slug=${1:-}
if [ -z "$slug" ]; then
  echo "usage: tools/capture-expected.sh <slug>" >&2
  exit 2
fi
code="$root/solutions/$slug"
[ -d "$code" ] || { echo "capture-expected: $code not found" >&2; exit 2; }
command -v node >/dev/null || { echo "capture-expected: node is required" >&2; exit 2; }

# tag::region[]
# region <commands.sh> <tag>: the text between '# tag::<tag>[]' and '# end::<tag>[]'.
region() {
  awk -v tag="$2" '
    $0 ~ "^[[:space:]]*# tag::" tag "\\[\\]$" { on = 1; next }
    $0 ~ "^[[:space:]]*# end::" tag "\\[\\]$" { on = 0 }
    on { print }' "$1"
}
# end::region[]

failed=0
written=0
cd "$code"
while IFS=$'\t' read -r step tag runnable expects; do
  [ -n "$step" ] || continue
  if [ "$runnable" != 1 ]; then
    echo "capture-expected: $step/$tag is [.manual], skipped"
    continue
  fi
  file="steps/$step/commands.sh"
  text=$(region "$file" "$tag")
  if [ -z "$text" ]; then
    echo "capture-expected: $step/$tag: tag not found in $file" >&2
    failed=1
    continue
  fi
  echo "capture-expected: $step/$tag"
  out=$(bash -c "set -euo pipefail
set -a; [ -f .env ] && . ./.env; set +a
$text" </dev/null 2>/tmp/capture-expected.err)
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "capture-expected: $step/$tag exited $rc:" >&2
    sed 's/^/  /' /tmp/capture-expected.err >&2
    failed=1
    continue
  fi
  target="steps/$step/expected/$tag.txt"
  if [ -n "$out" ] || [ "$expects" = 1 ]; then
    mkdir -p "steps/$step/expected"
    printf '%s\n' "$out" > "$target"
    written=$((written + 1))
  fi
done < <(node "$root/tools/gen-dd-specs.mjs" "$slug" --list)

echo "capture-expected: wrote $written file(s) under $code/steps/*/expected/"
[ $failed -eq 0 ]
