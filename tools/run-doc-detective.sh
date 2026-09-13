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
# The specFilter in the base config skips specs whose specId starts with "_",
# so _setup.json and _teardown.json only run through beforeAny/afterAll and
# never a second time as ordinary specs.
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

merged=$(mktemp "${TMPDIR:-/tmp}/dd-config-$slug.XXXXXX.json")
trap 'rm -f "$merged"' EXIT
jq -s '.[0] * .[1]' "$root/tools/doc-detective.base.json" "$local_cfg" > "$merged"

cd "$dir"
rm -f testResults-*.json
echo "run-doc-detective: $slug with doc-detective@$DD_VERSION"
npx --yes "doc-detective@$DD_VERSION" runTests --config "$merged" &
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
  kill -9 "$pid" 2>/dev/null || true
  pkill -9 -f "doc-detective" 2>/dev/null || true
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
