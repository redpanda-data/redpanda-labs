# Kafka Migration

Code for the Kafka Migration solution. The guided walkthrough lives on the docs site
at `/solutions/kafka-migration/`; this directory is what `make` drives and what the
download bundle contains.

## Run it

```bash
make up      # start the stack and wait for every healthcheck
make seed    # create topics and load sample data
make verify  # prints PASS (n/n) when the system does what the docs claim
make clean   # stop and delete volumes
```

`make help` lists every target. Versions are pinned in `.env` (copied from
`.env.example` on the first `make up`).

## Layout

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Redpanda, Redpanda Console, an `rpk` helper container, plus the solution's own services |
| `Makefile` | The `up`, `down`, `seed`, `verify`, `logs`, `clean`, `test-docs` contract |
| `scripts/verify.sh` | End-to-end checks; CI gates on its exit code |
| `sample-data/` | Deterministic seed data |
| `tests/doc-detective/` | One spec per documented step, plus `_setup` and `_teardown` |

## Docs

The pages under `docs/modules/kafka-migration/` in the repository read this directory
through symlinks: `include::example$...` shows code from here, and the
build-along files are published as attachments. Change code here and the docs
follow.
