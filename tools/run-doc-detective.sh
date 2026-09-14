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
# The step specs are generated into the run directory by tools/gen-dd-specs.mjs
# from the pages themselves (every command block, in :page-solution-steps:
# order), so nothing is committed per step and nothing drifts. _setup.json
# and _teardown.json (compose up and down) stay hand-written and only run
# through beforeAny/afterAll.
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
command -v node >/dev/null || { echo "run-doc-detective: node is required" >&2; exit 2; }
steps=$(awk 'NR==1 && /^= /{next} /^[[:space:]]*$/{exit} /^:page-solution-steps:/{sub(/^:page-solution-steps:[[:space:]]*/,""); print}' "$overview" | tr ',' ' ')

# BSD mktemp only substitutes trailing X characters, so make a run directory
# and give the merged config and the generated specs fixed names inside it.
run_dir=$(mktemp -d "${TMPDIR:-/tmp}/dd-config-$slug.XXXXXX")
merged="$run_dir/config.json"
trap 'rm -rf "$run_dir"' EXIT

# Generate one spec per step from the pages. --out writes nothing when a page
# has a problem, and the generator says which.
node "$root/tools/gen-dd-specs.mjs" "$slug" --out "$run_dir/specs" || { echo "run-doc-detective: spec generation failed" >&2; exit 2; }
inputs=()
for s in $steps; do
  spec="$run_dir/specs/$s.json"
  [ -f "$spec" ] || { echo "run-doc-detective: no generated spec for step '$s'" >&2; exit 2; }
  inputs+=("$spec")
done
[ ${#inputs[@]} -gt 0 ] || { echo "run-doc-detective: no steps listed in $overview" >&2; exit 2; }

# --input is not variadic in doc-detective 4.38.1, so the step specs go into
# the merged config's input array (absolute paths into the run directory).
# Never pass the committed specs directory: _setup and _teardown would then
# run a second time as ordinary specs.
inputs_json=$(printf '%s\n' "${inputs[@]}" | jq -R . | jq -s .)
jq -s --argjson inputs "$inputs_json" '.[0] * .[1] * {input: $inputs}' \
  "$root/tools/doc-detective.base.json" "$local_cfg" > "$merged"

cd "$dir"
rm -f testResults-*.json
echo "run-doc-detective: $slug with doc-detective@$DD_VERSION"
echo "run-doc-detective: generated specs for: $steps"
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

# Doc Detective keeps a full report directory per run under
# .doc-detective/runs/, screenshots and recordings included, and never prunes
# them. A day of runs is gigabytes, so keep the newest two (this run and the
# one to compare it with) and delete the rest. Runs regardless of the verdict,
# because a failed run writes a report too.
if [ -d .doc-detective/runs ]; then
  ls -1dt .doc-detective/runs/*/ 2>/dev/null | tail -n +3 | while IFS= read -r old; do
    rm -rf "$old"
  done
fi

results=$(ls testResults-*.json 2>/dev/null | head -1)
if [ -z "$results" ]; then
  echo "run-doc-detective: no results file was written (exit $rc)" >&2
  exit 1
fi

# A skipped test is a failure too: Doc Detective skips a test when it cannot
# start the browser context its media steps need, and a spec that never ran
# proves nothing.
node -e '
  const r = require(process.argv[1]);
  const tests = (r.specs || []).flatMap((s) => s.tests || []);
  const failed = tests.filter((t) => t.result === "FAIL");
  const skipped = tests.filter((t) => t.result === "SKIPPED");
  const ran = tests.filter((t) => ["PASS", "FAIL", "WARNING"].includes(t.result));
  console.log(JSON.stringify(r.summary || {}, null, 2));
  if (ran.length === 0) { console.error("run-doc-detective: no test reached a verdict"); process.exit(1); }
  if (failed.length) { console.error("run-doc-detective: failed tests: " + failed.map((t) => t.testId).join(", ")); process.exit(1); }
  if (skipped.length) { console.error("run-doc-detective: skipped tests (a browser context could not start?): " + skipped.map((t) => t.testId).join(", ")); process.exit(1); }
' "$PWD/$results"

# The run passed (the verdict above exits non-zero otherwise, and set -e stops
# the script there), so record what it proved. Nothing at build time can see
# the generated specs -- they live in the run directory above and never reach
# the Antora catalog -- so this manifest is the only way a published page can
# be backed by the run that tested it. Written from the results file by the
# runner, never by hand and never by a model: see tools/write-verification.mjs.
#
# SOLUTIONS_SKIP_VERIFICATION exists for one caller: the nightly's
# investigation step, where a model may rerun this script to check a fix. The
# manifest there must come from the workflow's own rerun after the change has
# been through the allowlist guard, so the agent's rerun must not write one.
#
# A manifest that cannot be written is a warning, not a failure: the test
# verdict is what this script exists to report, and turning a green run red
# over its own bookkeeping would be the wrong trade. check-metadata.sh is
# what notices a published solution with no manifest.
if [ "$rc" -eq 0 ] && [ -z "${SOLUTIONS_SKIP_VERIFICATION:-}" ]; then
  node "$root/tools/write-verification.mjs" "$slug" "$PWD/$results" || \
    echo "::warning::run-doc-detective: the run passed but its verification manifest could not be written" >&2
fi

exit "$rc"
