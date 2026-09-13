#!/usr/bin/env bash
# Run a solution's Doc Detective specs with the shared base config.
#
#   tools/run-doc-detective.sh <slug>
#
# Doc Detective has no "extends", so the per-solution
# solutions/<slug>/tests/doc-detective/.doc-detective.json holds only what
# differs (input, beforeAny, afterAll) and this script merges it over
# tools/doc-detective.base.json before running. The engine version is pinned
# on purpose: a bare `npx doc-detective` self-updates before every run.
#
# The specs to run are derived from :page-solution-steps: on the overview page
# (one spec per step id), so _setup.json and _teardown.json only run through
# beforeAny/afterAll and nothing has to be registered by hand.
set -euo pipefail

DD_VERSION=${DD_VERSION:-4.38.1}
root=$(cd "$(dirname "$0")/.." && pwd)
slug=${1:-}

if [ -z "$slug" ]; then
  echo "usage: tools/run-doc-detective.sh <slug>" >&2
  exit 2
fi

dir="$root/solutions/$slug"
local_cfg="$dir/tests/doc-detective/.doc-detective.json"
[ -f "$local_cfg" ] || { echo "run-doc-detective: $local_cfg not found" >&2; exit 2; }
command -v jq >/dev/null || { echo "run-doc-detective: jq is required" >&2; exit 2; }

overview="$root/docs/modules/$slug/pages/index.adoc"
[ -f "$overview" ] || { echo "run-doc-detective: $overview not found" >&2; exit 2; }
steps=$(awk 'NR==1 && /^= /{next} /^[[:space:]]*$/{exit} /^:page-solution-steps:/{sub(/^:page-solution-steps:[[:space:]]*/,""); print}' "$overview" | tr ',' ' ')
inputs=()
for s in $steps; do
  spec="tests/doc-detective/specs/$s.json"
  [ -f "$dir/$spec" ] || { echo "run-doc-detective: step '$s' has no spec $spec (run tools/check-metadata.sh)" >&2; exit 2; }
  inputs+=("$spec")
done
[ ${#inputs[@]} -gt 0 ] || { echo "run-doc-detective: no steps listed in $overview" >&2; exit 2; }

# --input is not variadic in doc-detective 4.38.1, so the step specs go into
# the merged config's input array. Never pass the specs directory: _setup and
# _teardown would then run a second time as ordinary specs.
merged=$(mktemp "${TMPDIR:-/tmp}/dd-config-$slug.XXXXXX.json")
trap 'rm -f "$merged"' EXIT
inputs_json=$(printf '%s\n' "${inputs[@]}" | jq -R . | jq -s .)
jq -s --argjson inputs "$inputs_json" '.[0] * .[1] * {input: $inputs}' \
  "$root/tools/doc-detective.base.json" "$local_cfg" > "$merged"

cd "$dir"
rm -f testResults-*.json
echo "run-doc-detective: $slug with doc-detective@$DD_VERSION"
echo "run-doc-detective: specs: ${inputs[*]}"
npx --yes "doc-detective@$DD_VERSION" --config "$merged" &
pid=$!

# The CLI has been seen to finish and then not exit. Poll for the results
# file, give it a moment to flush, then stop waiting.
for _ in $(seq 1 180); do
  if ! kill -0 "$pid" 2>/dev/null; then break; fi
  if ls testResults-*.json >/dev/null 2>&1; then sleep 15; break; fi
  sleep 10
done

rc=0
if kill -0 "$pid" 2>/dev/null; then
  echo "run-doc-detective: engine still running after results were written; stopping it" >&2
  kill -9 "$pid" 2>/dev/null || true
  # Only the engine's node process. A bare "doc-detective" pattern would match
  # this script too.
  pkill -9 -f 'node .*doc-detective' 2>/dev/null || true
else
  wait "$pid" || rc=$?
fi

results=$(ls testResults-*.json 2>/dev/null | head -1)
if [ -z "$results" ]; then
  echo "run-doc-detective: no results file was written (exit $rc)" >&2
  exit 1
fi

node -e '
  const r = require(process.argv[1]);
  const tests = (r.specs || []).flatMap((s) => s.tests || []);
  const failed = tests.filter((t) => t.result === "FAIL");
  const ran = tests.filter((t) => ["PASS", "FAIL", "WARNING"].includes(t.result));
  console.log(JSON.stringify(r.summary || {}, null, 2));
  if (ran.length === 0) { console.error("run-doc-detective: no test reached a verdict"); process.exit(1); }
  if (failed.length) { console.error("run-doc-detective: failed tests: " + failed.map((t) => t.testId).join(", ")); process.exit(1); }
' "$PWD/$results"
exit "$rc"
