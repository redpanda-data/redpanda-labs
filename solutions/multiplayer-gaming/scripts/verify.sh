#!/usr/bin/env bash
# Prove that Multiplayer Gaming works end to end.
#
# Run from the solution directory after `make up` and `make seed`:
#   ./scripts/verify.sh
# Prints "PASS (9/9)" and exits 0, or lists the failed checks and exits 1.
# CI and the last step of the solution both gate on this exit code. Each check
# is one claim the steps make about the running system.
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
SIM=http://localhost:${SIMULATOR_PORT:-8090}
LEADERBOARD=http://localhost:${LEADERBOARD_PORT:-3000}
ACHIEVEMENTS=http://localhost:${ACHIEVEMENTS_PORT:-3010}
CONNECT=http://localhost:${CONNECT_PORT:-4195}

# </dev/null: docker compose exec forwards stdin, which would eat the loop input in check 5.
psql_q() { docker compose exec -T postgres psql -U "${POSTGRES_USER:-game}" -d "${POSTGRES_DB:-game}" -tA -c "$1" 2>/dev/null </dev/null | tr -d '[:space:]'; }
# The compacted topic, read from the start to the current end and reduced the
# way compaction reduces it: the last record per key wins. One "player=score"
# line per player, so the checks below do not depend on how far compaction
# has run. Keys and decoded values come out of rpk; awk keeps the last score
# it sees for each key.
board() {
  rpk_exec topic consume game.leaderboard -o :end --use-schema-registry=value -f '%k\t%v\n' 2>/dev/null </dev/null \
    | awk -F'\t' '{ s=$2; sub(/.*"score": *"?/, "", s); sub(/[^-0-9].*/, "", s); last[$1]=s } END { for (k in last) printf "%s=%s\n", k, last[k] }'
}
board_top10() { board | sort -t= -k2,2nr -k1,1 | head -10; }
hwm() { rpk_exec topic describe "$1" -p 2>/dev/null </dev/null | awk 'NR>1 {s+=$NF} END {print s+0}'; }
partitions() { rpk_exec topic describe "$1" -p 2>/dev/null </dev/null | awk 'NR>1 {n++} END {print n+0}'; }
stat() { curl -fsS "$SIM/stats" 2>/dev/null | sed -nE "s/.*\"$1\": *([0-9]+).*/\1/p" | head -1; }
stat_topic() { curl -fsS "$SIM/stats" 2>/dev/null | tr -d '\n ' | sed -nE "s/.*\"acked\":\{[^}]*\"$1\":([0-9]+).*/\1/p"; }

# tag::checks[]
# 1. The five topics exist with the documented partition counts, and the
#    leaderboard topic is compacted.
shape="game.player-events=$(partitions game.player-events) game.match-events=$(partitions game.match-events) game.achievements=$(partitions game.achievements) game.leaderboard=$(partitions game.leaderboard) game.player-events.dlq=$(partitions game.player-events.dlq) cleanup.policy=$(rpk_exec topic describe game.leaderboard -c 2>/dev/null </dev/null | awk '$1=="cleanup.policy" {print $2}')"
assert_eq "topics and partitions" "game.player-events=6 game.match-events=3 game.achievements=3 game.leaderboard=3 game.player-events.dlq=1 cleanup.policy=compact" "$shape"

# 2. Every record the simulator had acknowledged is on the log, and no more.
#    Before any burst the total is exactly SIM_EVENTS_MAX.
generated=$(stat generated_total); burst=$(stat burst_events); poison=$(stat poison_records); events_max=$(stat events_max)
expected_player=$(( $(stat_topic game.player-events) + poison ))
expected_match=$(stat_topic game.match-events)
actual="player-events=$(hwm game.player-events) match-events=$(hwm game.match-events)"
if [ "${burst:-0}" -eq 0 ] && [ "${generated:-0}" -ne "${events_max:-0}" ]; then
  fail "high watermarks match the simulator (generated $generated events, expected exactly $events_max)"
else
  assert_eq "high watermarks match the simulator (SIM_EVENTS_MAX=$events_max, burst=$burst, poison=$poison)" "player-events=$expected_player match-events=$expected_match" "$actual"
fi

# 3. Every consumer group has caught up.
lag_total() { rpk_exec group describe leaderboard achievements connect-history 2>/dev/null | awk '$1 ~ /^game\./ && $6 ~ /^[0-9]+$/ {s+=$6} END {print s+0}'; }
retry 30 2 sh -c '[ "$(docker compose exec -T rpk rpk group describe leaderboard achievements connect-history 2>/dev/null | awk '"'"'$1 ~ /^game\./ && $6 ~ /^[0-9]+$/ {s+=$6} END {print s+0}'"'"')" = "0" ]' >/dev/null
assert_eq "consumer groups leaderboard, achievements, connect-history have lag 0" 0 "$(lag_total)"

# tag::board[]
# 4. After dedupe by key, game.leaderboard holds one live entry per player
#    that ever scored, according to Postgres.
snapshot=$(board)
assert_eq "game.leaderboard has one live entry per scoring player (last record per key)" "$(psql_q "SELECT COUNT(DISTINCT player_id) FROM player_events WHERE event_type='score_changed'")" "$(printf '%s\n' "$snapshot" | grep -c .)"

# 5. The top 10 totals on game.leaderboard equal the sum of deltas in Postgres,
#    and the dashboard, which reads the same topic, serves the same ten.
top=$(printf '%s\n' "$snapshot" | sort -t= -k2,2nr -k1,1 | head -10 | sort)
ids=$(printf '%s\n' "$top" | cut -d= -f1 | sed "s/.*/'&'/" | paste -sd, -)
db=$(psql_q "SELECT string_agg(player_id || '=' || total, ',' ORDER BY player_id) FROM (SELECT player_id, SUM(delta) AS total FROM player_events WHERE event_type='score_changed' AND player_id IN ($ids) GROUP BY 1) t")
dash_top() { curl -fsS "$LEADERBOARD/api/top" 2>/dev/null | tr -d '\n ' | grep -oE '"player_id":"[^"]+","display_name":"[^"]*","score":-?[0-9]+' | sed -E 's/"player_id":"([^"]+)","display_name":"[^"]*","score":(-?[0-9]+)/\1=\2/' | sort | paste -sd, -; }
dash_agrees() { [ "$(dash_top)" = "$db" ]; }
retry 10 1 dash_agrees >/dev/null
if [ "$(printf '%s\n' "$top" | wc -l | tr -d ' ')" = "10" ] && [ "$(printf '%s\n' "$top" | paste -sd, -)" = "$db" ] && [ "$(dash_top)" = "$db" ]; then
  pass "top 10 totals on game.leaderboard equal SUM(delta) in Postgres and the dashboard's /api/top"
else
  fail "top 10 totals on game.leaderboard equal SUM(delta) in Postgres and the dashboard's /api/top (topic: $(printf '%s\n' "$top" | paste -sd, -); postgres: $db; dashboard: $(dash_top))"
fi
# end::board[]

# 6. Every finished match has a history row.
assert_eq "match_history rows equal match_ended events" "$(stat match_ended)" "$(psql_q "SELECT COUNT(*) FROM match_history")"

# 7. Achievements fired and every unlock is on game.achievements.
unlocked=$(curl -fsS "$ACHIEVEMENTS/healthz" 2>/dev/null | tr -d '\n ' )
hot=$(printf '%s' "$unlocked" | sed -nE 's/.*"hot_streak":([0-9]+).*/\1/p'); total=$(printf '%s' "$unlocked" | sed -nE 's/.*"unlocked_total":([0-9]+).*/\1/p')
if [ "${hot:-0}" -ge 1 ] && [ "$(hwm game.achievements)" = "${total:-x}" ]; then pass "achievements: hot_streak fired (${hot}) and all $total unlocks are on game.achievements"; else fail "achievements: hot_streak fired and all unlocks are on game.achievements (hot_streak=${hot:-0}, unlocked=$total, on topic $(hwm game.achievements))"; fi

# 8. The dead-letter topic holds exactly the poison records, nothing else.
dlq_expected=${poison:-0}
retry 15 2 sh -c "[ \"\$(docker compose exec -T rpk rpk topic describe game.player-events.dlq -p 2>/dev/null | awk 'NR>1 {s+=\$NF} END {print s+0}')\" = \"$dlq_expected\" ]" >/dev/null
assert_eq "game.player-events.dlq holds exactly the poison records ($dlq_expected)" "$dlq_expected" "$(hwm game.player-events.dlq)"

# 9. The dashboard and the Connect pipeline answer.
if http_ok "$LEADERBOARD/api/top" && http_ok "$CONNECT/ready"; then pass "leaderboard dashboard and Connect /ready answer"; else fail "leaderboard dashboard and Connect /ready answer"; fi
# end::checks[]

verify_summary
