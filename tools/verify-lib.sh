#!/usr/bin/env bash
# Shared assertions for solutions/<slug>/scripts/verify.sh.
#
# Source this file, do not execute it:
#
#   . "$(dirname "$0")/../../../tools/verify-lib.sh" 2>/dev/null || . ./verify-lib.sh
#
# Every check calls pass or fail. Call verify_summary last: it prints
# "PASS (n/n)" and exits 0, or lists every failed check, prints
# "FAIL (passed/total)" and exits 1. CI gates on that exit code.

VERIFY_PASS=0
VERIFY_FAIL=0
VERIFY_FAILED_CHECKS=""

pass() {
  VERIFY_PASS=$((VERIFY_PASS + 1))
  printf 'ok    %s\n' "$1"
}

fail() {
  VERIFY_FAIL=$((VERIFY_FAIL + 1))
  VERIFY_FAILED_CHECKS="${VERIFY_FAILED_CHECKS}  - ${1}"$'\n'
  printf 'FAIL: %s\n' "$1" >&2
}

# assert_eq <check name> <expected> <actual>
assert_eq() {
  local name=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    pass "$name"
  else
    fail "$name (expected '$expected', got '$actual')"
  fi
}

# assert_ge <check name> <actual> <minimum>   (integers)
assert_ge() {
  local name=$1 actual=$2 min=$3
  if [ "$actual" -ge "$min" ] 2>/dev/null; then
    pass "$name"
  else
    fail "$name (expected >= $min, got '$actual')"
  fi
}

# assert_contains <check name> <needle> <haystack>
assert_contains() {
  local name=$1 needle=$2 haystack=$3
  case "$haystack" in
    *"$needle"*) pass "$name" ;;
    *) fail "$name (expected output to contain '$needle')" ;;
  esac
}

# assert_cmd <check name> <command...>   passes when the command exits 0
assert_cmd() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name (command failed: $*)"
  fi
}

# retry <attempts> <delay seconds> <command...>
# Runs the command until it exits 0 or the attempts run out.
retry() {
  local attempts=$1 delay=$2 n=1
  shift 2
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then
      return 1
    fi
    n=$((n + 1))
    sleep "$delay"
  done
}

# rpk_exec <rpk args...>
# Runs rpk inside the compose project's rpk helper container so the script
# does not depend on a host install. Override RPK_SERVICE to target another
# service; set COMPOSE_FILE (compose honours it) to point at another file.
rpk_exec() {
  docker compose exec -T "${RPK_SERVICE:-rpk}" rpk "$@"
}

# compose_exec <service> <command...>
compose_exec() {
  local service=$1
  shift
  docker compose exec -T "$service" "$@"
}

# http_ok <url>   exits 0 when the URL answers 2xx or 3xx
http_ok() {
  curl -fsS -o /dev/null "$1"
}

verify_summary() {
  local total=$((VERIFY_PASS + VERIFY_FAIL))
  if [ "$VERIFY_FAIL" -eq 0 ]; then
    printf 'PASS (%d/%d)\n' "$VERIFY_PASS" "$total"
    exit 0
  fi
  printf '\nFailed checks:\n%s' "$VERIFY_FAILED_CHECKS" >&2
  printf 'FAIL (%d/%d)\n' "$VERIFY_PASS" "$total"
  exit 1
}
