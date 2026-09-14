#!/usr/bin/env bash
# Is every path the nightly's investigation touched one it is allowed to change?
#
#   git status --porcelain ... | tools/nightly-allowed-change.sh [--with-verification] <slug>
#   printf '%s\n' path1 path2 | tools/nightly-allowed-change.sh <slug>
#
# Reads repository-relative paths on stdin, one per line, and exits 0 only when
# every one of them is inside this solution's allowlist:
#
#   solutions/<slug>/steps/<step-id>/expected/<name>.txt   a captured output
#   docs/modules/<slug>/images/<file>                      a captured screenshot or recording
#   solutions/<slug>/.env.example                          the pinned image versions
#
# With --with-verification, one more:
#
#   docs/modules/<slug>/attachments/verification.json      the run's own manifest
#
# That file is evidence of what a test run proved, so only the runner may
# produce it (tools/write-verification.mjs, called by
# tools/run-doc-detective.sh on a passing run). The nightly passes the flag on
# the two paths where the manifest comes from its own run, and withholds it
# when checking what the investigating model changed: a manifest appearing
# there would mean the model wrote one, which is exactly what must never ship.
#
# Anything else, and the offending paths go to stdout and it exits 1. This is
# the mechanical half of the nightly's promise: the agent that investigates a
# failing spec may refresh what the tests capture and the versions they run
# against, and may not touch what the tests assert. A failing assertion must
# never be resolvable by editing the assertion, so scripts/verify.sh, any
# commands.sh, any page, any media.json and any service source are outside the
# list, and so is every path belonging to another solution.
#
# No paths at all is success: the caller decides what an empty change set
# means (for the nightly it means the agent proposed no fix).
set -uo pipefail

with_verification=""
slug=""
for arg in "$@"; do
  case "$arg" in
    --with-verification) with_verification=1 ;;
    -*) echo "nightly-allowed-change: unknown option $arg" >&2; exit 2 ;;
    *) slug=$arg ;;
  esac
done
if [ -z "$slug" ]; then
  echo "usage: tools/nightly-allowed-change.sh [--with-verification] <slug> (paths on stdin)" >&2
  exit 2
fi

allowed() {
  local p=$1 rest
  case "$p" in
    "solutions/$slug/.env.example")
      return 0
      ;;
    "docs/modules/$slug/attachments/verification.json")
      [ -n "$with_verification" ] && return 0
      return 1
      ;;
    "solutions/$slug/steps/"*)
      # Exactly steps/<step-id>/expected/<name>.txt, which is two slashes. A
      # `case` glob matches a slash, so the depth has to be bounded separately:
      # three or more slashes means something deeper than one step's expected/
      # directory, and a step id never contains a slash.
      rest=${p#"solutions/$slug/steps/"}
      case "$rest" in
        */*/*/*) return 1 ;;
        *) ;;
      esac
      case "$rest" in
        */expected/*.txt) ;;
        *) return 1 ;;
      esac
      case "$rest" in
        *..*) return 1 ;;
        *) return 0 ;;
      esac
      ;;
    "docs/modules/$slug/images/"*)
      # One level only: images/<file>, no subdirectories, and a name is required.
      rest=${p#"docs/modules/$slug/images/"}
      [ -n "$rest" ] || return 1
      case "$rest" in
        */*|*..*) return 1 ;;
        *) return 0 ;;
      esac
      ;;
  esac
  return 1
}

violations=0
while IFS= read -r path; do
  # Skip blank lines so a trailing newline from git is not a violation.
  [ -n "$path" ] || continue
  if ! allowed "$path"; then
    echo "$path"
    violations=$((violations + 1))
  fi
done

[ "$violations" -eq 0 ]
