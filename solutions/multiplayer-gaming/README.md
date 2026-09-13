# Multiplayer Gaming

Code for the Multiplayer Gaming solution: game events with a live leaderboard,
achievements, and a match history, on Redpanda. The guided walkthrough lives
on the docs site at `/solutions/multiplayer-gaming/`; this directory is what
`make` drives and what the download bundle contains.

## Run it

```bash
make up       # build the Go services, start the stack, wait for every healthcheck
make topics   # game.player-events (6p), game.match-events (3p), game.achievements (3p), game.player-events.dlq (1p)
make schemas  # register GameEvent v1, set BACKWARD, register v2 on the three <topic>-value subjects
make seed     # topics + schemas, then wait for the simulator to produce exactly SIM_EVENTS_MAX events
make verify   # prints PASS (9/9) when the system does what the docs claim
make clean    # stop and delete volumes
```

`make help` lists every target. Versions and simulator settings are pinned in
`.env` (copied from `.env.example` on the first `make up`).

Then open:

| URL | What |
|---|---|
| http://localhost:3000 | live leaderboard dashboard (top 10, group members, consumer lag) |
| http://localhost:8080 | Redpanda Console, Protobuf records decoded through Schema Registry |
| http://localhost:8090/stats | simulator counters; `POST /burst?rate=&seconds=` and `POST /poison` |
| http://localhost:3010/healthz | achievements service: players tracked, unlocks by name |
| http://localhost:4195/ready | Redpanda Connect pipeline |

## Layout

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Redpanda, Console, an `rpk` helper, Redis, Postgres, Redpanda Connect, the three Go services, and the leaderboard dashboard (the leaderboard binary in dashboard role) |
| `Makefile` | `up`, `down`, `topics`, `schemas`, `seed`, `verify`, `logs`, `clean`, `proto`, `test`, `test-docs` |
| `proto/game_events.proto` | the `GameEvent` contract (version 2); `proto/history/` holds version 1 and a deliberately breaking change |
| `buf.yaml`, `buf.gen.yaml` | `make proto` regenerates `services/internal/gamepb/` with buf in a container |
| `services/` | one Go module: `simulator`, `leaderboard`, `achievements`, shared `internal/` packages, one `Dockerfile` |
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
