#!/usr/bin/env bash
# Prove that the sports data feed fan-out works end to end.
#
# Run from the solution directory after `make up` and `make seed`:
#   ./scripts/verify.sh
# Prints "PASS (8/8)" and exits 0, or lists the failed checks and exits 1.
# CI and the last step of the solution both gate on this exit code. Each check
# is one claim the steps make about the running system.
#
# Every check is a statement about state, not about text: the number of
# records on a topic, the lag of a group, the rows in Postgres. That is what
# makes the same script the truth on a laptop and on Redpanda Cloud, where the
# numbers in the docs would all be different.
#
# Every number comes from the log or from Postgres, never from a service's
# in-memory counters. That is deliberate: restarting the odds engine resets
# its counters while the topics keep everything, and a verify script that
# reported FAIL on a healthy system after a restart would be worse than no
# verify script. It also means these checks stay true after `make evolve`
# starts a second feed.
set -uo pipefail
cd "$(dirname "$0")/.."

# verify-lib.sh lives in tools/ in the repo. The published attachments and the
# release bundle carry a copy next to this script.
if [ -f ../../tools/verify-lib.sh ]; then
  . ../../tools/verify-lib.sh
elif [ -f scripts/verify-lib.sh ]; then
  . scripts/verify-lib.sh
else
  echo "verify: verify-lib.sh not found (expected ../../tools/verify-lib.sh or scripts/verify-lib.sh)" >&2
  exit 2
fi

# Read .env the way Compose does: a variable already set in the shell wins.
if [ -f .env ]; then
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue ;; esac
    [ -z "${!k:-}" ] && export "$k=$v"
  done < .env
fi
FEED=http://localhost:${FEED_PORT:-8090}
STATE=http://localhost:${MARKET_STATE_PORT:-3010}
CONNECT=http://localhost:${CONNECT_PORT:-4195}
# The latency budget the solution claims. Overridable because a laptop under a
# docker build and a Cloud round trip are not the same machine, but the
# default is the number the docs quote.
BUDGET_MS=${LATENCY_BUDGET_MS:-1000}

# </dev/null: docker compose exec forwards stdin, which would eat loop input.
psql_q() { docker compose exec -T postgres psql -U "${POSTGRES_USER:-sports}" -d "${POSTGRES_DB:-sports}" -tA -c "$1" 2>/dev/null </dev/null | tr -d '[:space:]'; }
hwm() { rpk_exec topic describe "$1" -p 2>/dev/null </dev/null | awk 'NR>1 {s+=$NF} END {print s+0}'; }
partitions() { rpk_exec topic describe "$1" -p 2>/dev/null </dev/null | awk 'NR>1 {n++} END {print n+0}'; }
# TOTAL-LAG summed over the three groups, and the number of groups that
# answered: a group that is missing must not read as lag 0.
group_lag() { rpk_exec group describe odds-engine market-state feed-archive 2>/dev/null </dev/null | awk '$1=="TOTAL-LAG" {s+=$2} END {print s+0}'; }
groups_seen() { rpk_exec group describe odds-engine market-state feed-archive 2>/dev/null </dev/null | awk '$1=="GROUP" {n++} END {print n+0}'; }
json_num() { sed -nE "s/.*\"$1\": *([0-9]+).*/\1/p" | head -1; }
feed_stat() { curl -fsS "$FEED/healthz" 2>/dev/null | json_num "$1"; }
state_stat() { curl -fsS "$STATE/healthz" 2>/dev/null | tr -d '\n ' | sed -nE "s/.*\"$1\":([0-9]+).*/\1/p" | head -1; }
odds_stat() { curl -fsS "http://localhost:${ODDS_PORT:-0}/healthz" 2>/dev/null | json_num "$1"; }
# The odds engine has no published port (it scales), so its numbers come from
# inside the network. Used for context in failure messages, never asserted on.
odds_health() { docker compose exec -T odds-engine wget -qO- http://localhost:8080/healthz 2>/dev/null </dev/null | tr -d '\n '; }

# Each topic decoded to one JSON object per line. --use-schema-registry=value
# is what makes this readable: rpk reads the schema ID in each record and
# fetches the schema, so a topic holding two versions still comes out as JSON.
consume() { rpk_exec topic consume "$1" -o :end --use-schema-registry=value -f "${2:-%v\n}" 2>/dev/null </dev/null; }
field() { sed -nE "s/.*\"$1\":\"?([^,\"}]*)\"?.*/\1/p"; }

# tag::checks[]
# 1. The topics exist with the documented partition counts, and the desk's
#    view is compacted. A non-compacted market-state topic would grow without
#    bound and lose the property the solution is built on.
shape="sports.feed=$(partitions sports.feed) sports.odds=$(partitions sports.odds) sports.market-state=$(partitions sports.market-state) sports.feed.dlq=$(partitions sports.feed.dlq) cleanup.policy=$(rpk_exec topic describe sports.market-state -c 2>/dev/null </dev/null | awk '$1=="cleanup.policy" {print $2}')"
assert_eq "topics and partitions" "sports.feed=6 sports.odds=6 sports.market-state=3 sports.feed.dlq=1 cleanup.policy=compact" "$shape"

# 2. The feed lost nothing: it failed no publish, and everything it
#    acknowledged is on the log. Stated as ">=" rather than "==" on purpose,
#    because `make evolve` starts a second feed whose counter begins at zero
#    while the topic keeps every earlier event. Check 8 is what pins the exact
#    total, from the log's own side.
produced=$(feed_stat produced); failed=$(feed_stat failed)
feed_hwm=$(hwm sports.feed)
if [ "${failed:-1}" = 0 ] && [ "${feed_hwm:-0}" -ge "${produced:-1}" ] 2>/dev/null; then
  pass "the feed lost nothing (produced=$produced, failed=$failed, on the log=$feed_hwm)"
else
  fail "the feed lost nothing (produced=$produced, failed=$failed, on the log=$feed_hwm)"
fi

# 3. All three consumer groups have caught up. This is the fan-out claim: one
#    topic, three groups, all current.
seen=$(groups_seen); lag=$(group_lag)
if [ "$seen" = 3 ] && [ "$lag" = 0 ]; then
  pass "all three consumer groups (odds-engine, market-state, feed-archive) have lag 0"
else
  fail "all three consumer groups have lag 0 (groups described: $seen of 3, total lag: $lag)"
fi

# 4. Every market that got a priceable update has a price on sports.odds, and
#    sports.odds invented nothing. Set equality, not counts: a missing market
#    is the failure a price feed cannot have, and it names which one.
feed_records=$(consume sports.feed)
odds_records=$(consume sports.odds)
updated_markets=$(printf '%s\n' "$feed_records" | grep '"event_type":"MARKET_UPDATE"' | field market_id | sort -u)
priced_markets=$(printf '%s\n' "$odds_records" | field market_id | sort -u)
missing=$(comm -23 <(printf '%s\n' "$updated_markets") <(printf '%s\n' "$priced_markets") | tr '\n' ' ')
invented=$(comm -13 <(printf '%s\n' "$updated_markets") <(printf '%s\n' "$priced_markets") | tr '\n' ' ')
n_updated=$(printf '%s\n' "$updated_markets" | grep -c .)
if [ -z "${missing// /}" ] && [ -z "${invented// /}" ] && [ "$n_updated" -ge 1 ]; then
  pass "every one of the $n_updated markets that got an update has a price on sports.odds, and no others do"
else
  fail "sports.odds covers exactly the updated markets (updated=$n_updated, never priced: ${missing:-none}, priced but never updated: ${invented:-none})"
fi

# 5. No impossible price reached a screen: every price is inside the book's
#    publishable range, and none was published before the event that caused
#    it. Both are data errors a consumer cannot detect on its own.
prices=$(printf '%s\n' "$odds_records" | field price)
bad_price=$(printf '%s\n' "$prices" | awk '$1 < 1.01 || $1 > 1000 {n++} END {print n+0}')
n_prices=$(printf '%s\n' "$prices" | grep -c .)
backwards=$(printf '%s\n' "$odds_records" | sed -nE 's/.*"feed_ts":([0-9]+),"priced_ts":([0-9]+).*/\1 \2/p' | awk '$2 < $1 {n++} END {print n+0}')
if [ "$n_prices" -ge 1 ] && [ "$bad_price" = 0 ] && [ "$backwards" = 0 ]; then
  pass "all $n_prices prices are within 1.01 and 1000, and none predates its event"
else
  fail "every price is publishable and none predates its event (prices=$n_prices, out of range=$bad_price, priced before the event=$backwards)"
fi

# 6. End-to-end latency, from the provider's emit time to the published price,
#    inside the budget at the 99th percentile. Computed from the records
#    themselves, so the reader can run the same command and get the same
#    number, and so a restart cannot flatter it.
latencies=$(printf '%s\n' "$odds_records" | sed -nE 's/.*"feed_ts":([0-9]+),"priced_ts":([0-9]+).*/\2 \1/p' | awk '{print $1-$2}' | sort -n)
n_lat=$(printf '%s\n' "$latencies" | grep -c .)
p99=$(printf '%s\n' "$latencies" | awk -v n="$n_lat" 'NR==int(0.99*(n-1))+1 {print; exit}')
if [ "${n_lat:-0}" -ge 100 ] && [ "${p99:-999999}" -le "$BUDGET_MS" ] 2>/dev/null; then
  pass "p99 feed-to-price latency ${p99}ms is within the ${BUDGET_MS}ms budget (${n_lat} priced events)"
else
  fail "p99 feed-to-price latency within ${BUDGET_MS}ms over at least 100 events (p99=${p99:-none}ms, events=${n_lat:-0})"
fi

# 7. The desk's view, read the way a new consumer would read it: the last
#    record per fixture on the compacted topic. Every fixture the feed
#    finished is settled there with no market left open, which is the state a
#    book must never get wrong.
#    awk keeps the last value per key, which is what compaction will leave.
state_last=$(consume sports.market-state '%k\t%v\n' | awk -F'\t' '{last[$1]=$2} END {for (k in last) print last[k]}')
n_state=$(printf '%s\n' "$state_last" | grep -c .)
n_settled=$(printf '%s\n' "$state_last" | grep -c '"settled":true')
n_open=$(printf '%s\n' "$state_last" | field open_markets | awk '{s+=$1} END {print s+0}')
ended=$(printf '%s\n' "$feed_records" | grep -c '"event_type":"MATCH_END"')
if [ "$n_state" -ge 1 ] && [ "$n_settled" = "$ended" ] && [ "$n_open" = 0 ]; then
  pass "the compacted desk view holds $n_state fixtures, all $n_settled finished ones settled with 0 markets open"
else
  fail "the compacted desk view settles every finished fixture with no open markets (fixtures=$n_state, settled=$n_settled, MATCH_END events=$ended, open markets=$n_open)"
fi

# 8. The archive mirrors the log exactly: one row for every record on
#    sports.feed, nothing missing and nothing invented, and nothing in the
#    dead-letter topic. This is the check that pins the totals, and it holds
#    however many times the feed has run, because the row's primary key is the
#    provider's (fixture, seq) and every event has its own.
rows=$(psql_q "SELECT COUNT(*) FROM feed_archive")
dlq=$(hwm sports.feed.dlq)
if [ "${rows:-0}" = "${feed_hwm:-x}" ] && [ "${dlq:-1}" = 0 ]; then
  pass "feed_archive holds one row for every record on sports.feed ($rows) and the dead-letter topic is empty"
else
  fail "feed_archive mirrors sports.feed and the DLQ is empty (rows=$rows, on the log=$feed_hwm, dlq=$dlq)"
fi
# end::checks[]

verify_summary
