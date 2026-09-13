# Multiplayer Gaming

Code for the Multiplayer Gaming solution: game events with a live leaderboard,
achievements, and a match history, on Redpanda. The guided walkthrough lives
on the docs site at `/solutions/multiplayer-gaming/`; this directory is what
`make` drives and what the download bundle contains.

## Run it

```bash
make up       # build the Go services, start the stack, wait for every healthcheck
make topics   # game.player-events (6p), game.match-events (3p), game.achievements (3p), game.leaderboard (3p, compacted), game.player-events.dlq (1p)
make schemas  # register GameEvent v1, set BACKWARD, register v2 on the three event subjects; register the current file on game.leaderboard-value
make seed     # topics + schemas, then wait for the simulator to produce exactly SIM_EVENTS_MAX events
make verify   # prints PASS (9/9) when the system does what the docs claim
make clean    # stop and delete volumes
```

`make help` lists every target. Versions and simulator settings are pinned in
`.env` (copied from `.env.example` on the first `make up`), and so are the
host ports (`CONSOLE_PORT`, `LEADERBOARD_PORT`, and the other `*_PORT`
variables). Change them there when another stack already uses the defaults.

### Run against Redpanda Cloud

The same stack runs against a Redpanda Cloud Serverless cluster. In `.env`,
set `COMPOSE_PROFILES=` (empty, so the local `redpanda` and `console`
containers are skipped), `REDPANDA_BROKERS` to the bootstrap server URL,
`REDPANDA_TLS_ENABLED=true`, `REDPANDA_SASL_MECHANISM=SCRAM-SHA-256`, the
user and password, `REDPANDA_SCHEMA_REGISTRY_URL`, and
`REDPANDA_TOPIC_REPLICAS=3`. The Go services (`services/internal/conn`), the
`rpk` helper, and the Connect pipeline all read those variables; nothing
else changes. `make tiered-up` is local only.

### Tiered Storage extension

`make tiered-up` starts the local stack plus MinIO (compose profile
`tiered`), points Redpanda at the bucket, and restarts the broker with
`cloud_storage_enabled=true`. It is the overview page's "Extend this
solution" section, not a step: `make verify` never depends on it.

Then open (default ports):

| URL | What |
|---|---|
| http://localhost:3000 | live leaderboard dashboard (top 10 read from `game.leaderboard`, group members, consumer lag); `/api/top`, `/api/status` |
| http://localhost:8080 | Redpanda Console, Protobuf records decoded through Schema Registry |
| http://localhost:8090/stats | simulator counters; `POST /burst?rate=&seconds=` and `POST /poison` |
| http://localhost:3010/healthz | achievements service: players tracked, unlocks by name |
| http://localhost:4195/ready | Redpanda Connect pipeline |

## Layout

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Redpanda and Console (profile `local`), an `rpk` helper, Postgres, Redpanda Connect, the three Go services, the leaderboard dashboard (a fourth Go program that only reads `game.leaderboard`), and MinIO (profile `tiered`) |
| `Makefile` | `up`, `down`, `topics`, `schemas`, `seed`, `verify`, `logs`, `clean`, `proto`, `test`, `test-docs`, `tiered-up` |
| `proto/game_events.proto` | the `GameEvent` contract (version 2) and the `LeaderboardEntry` published to `game.leaderboard`; `proto/history/` holds version 1 and a deliberately breaking change |
| `buf.yaml`, `buf.gen.yaml` | `make proto` regenerates `services/internal/gamepb/` with buf in a container |
| `services/` | one Go module: `simulator`, `leaderboard` (aggregates and publishes totals), `dashboard` (reads the compacted topic), `achievements`, shared `internal/` packages, one `Dockerfile` |
| `connect/match-history.yaml` | the Redpanda Connect pipeline: decode, flatten, insert, dead-letter on failure |
| `postgres/init.sql` | `match_history` and `player_events` tables |
| `console-config.yaml` | Redpanda Console with Schema Registry decoding |
| `sample-data/players.json` | the player roster the simulator uses |
| `scripts/verify.sh` | the nine end-to-end checks; CI gates on its exit code |
| `tests/doc-detective/` | one spec per documented step, plus `_setup` and `_teardown` |

## Change the code

- Edit `proto/game_events.proto`, run `make proto`, commit the generated file.
- `make test` runs `go vet` and the unit tests (achievement rules, simulator
  determinism) in a Go container. With Go installed, `cd services && go test ./...`
  works too.
- `make up` rebuilds the service images.

## Docs

The pages under `docs/modules/multiplayer-gaming/` in the repository read this
directory through symlinks: `include::example$...` shows code from here, and
the build-along files are published as attachments. Change code here and the
docs follow.
