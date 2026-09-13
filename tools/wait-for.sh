#!/usr/bin/env bash
# Wait until a command succeeds or an HTTP endpoint answers.
#
#   tools/wait-for.sh [--timeout 120] [--interval 2] --http http://localhost:8080/ready
#   tools/wait-for.sh [--timeout 120] [--interval 2] -- docker compose exec -T rpk rpk cluster health --exit-when-healthy
#
# Exits 0 as soon as the probe succeeds, 1 when the timeout passes.
set -u

timeout=120
interval=2
url=""

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) timeout=$2; shift 2 ;;
    --interval) interval=$2; shift 2 ;;
    --http) url=$2; shift 2 ;;
    --) shift; break ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) break ;;
  esac
done

if [ -z "$url" ] && [ $# -eq 0 ]; then
  echo "wait-for: give --http <url> or a command after --" >&2
  exit 2
fi

deadline=$(( $(date +%s) + timeout ))
while :; do
  if [ -n "$url" ]; then
    curl -fsS -o /dev/null "$url" 2>/dev/null && exit 0
  else
    "$@" >/dev/null 2>&1 && exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    if [ -n "$url" ]; then
      echo "wait-for: $url did not answer within ${timeout}s" >&2
    else
      echo "wait-for: '$*' did not succeed within ${timeout}s" >&2
    fi
    exit 1
  fi
  sleep "$interval"
done
