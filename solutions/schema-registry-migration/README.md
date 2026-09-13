# Schema Registry Migration

Code for the Schema Registry Migration solution: move a Confluent deployment,
schemas and topic data together, onto Redpanda with one shadow link. The guided
walkthrough lives on the docs site at `/solutions/schema-registry-migration/`;
this directory is what `make` drives and what the download bundle contains.

## Run it

```bash
make up        # build the client image, start Confluent (broker + Schema Registry), Redpanda, Console, wait for healthchecks
make seed      # register the six subjects on the Confluent registry and produce 6 Avro records to the Confluent broker
make migrate   # create the shadow link, wait for schemas and topics, pause schema replication, fail the topics over, produce on Redpanda
make verify    # prints PASS (18/18) when the migration reached its end state
make clean     # stop and delete volumes
```

`make help` lists every target, including the single steps the walkthrough
uses (`register-schemas`, `link`, `compare`, `produce`, `consume`,
`consume-shadow-registry`, `consume-redpanda`, `wait-topics`, `pause`,
`failover`, `produce-redpanda`). Versions and host ports are pinned in `.env`
(copied from `.env.example` on the first `make up`). The defaults leave the
ports of the other solutions free, so this stack can run next to them.

Then open (default ports):

| URL | What |
|---|---|
| http://localhost:8180 | Redpanda Console, connected to the Redpanda shadow cluster: the replicated subjects and topics |
| http://localhost:28081 | Schema Registry of the Redpanda cluster (REST) |
| http://localhost:38081 | Confluent Schema Registry (REST, the source; no UI) |

## Layout

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Confluent broker and Schema Registry (source), Redpanda with Shadowing enabled (destination), Redpanda Console, an `rpk` helper, and the Python client |
| `Makefile` | `up`, `down`, `seed`, `migrate`, `verify`, `logs`, `clean`, `test-docs`, plus the single migration steps |
| `config/shadow-link.yaml` | The shadow link: API-mode Schema Registry replication and topic metadata sync |
| `client/` | The client image: Python with confluent-kafka, fastavro, requests, curl, and jq |
| `schemas/` | The Avro, JSON Schema, and Protobuf schemas registered on the source |
| `sample-data/` | The records the client produces, before and after cut-over |
| `scripts/register-schemas.sh`, `scripts/register-complex-schemas.sh` | REST calls against the source registry |
| `scripts/compare_registries.py` | Compares both registries subject by subject; polls until they agree |
| `scripts/produce_topic_data.py`, `scripts/consume_topic_data.py` | Avro records in the Confluent wire format, endpoints chosen by environment variables |
| `scripts/set-paused.sh` | Pauses or resumes schema replication through a non-interactive `rpk shadow update` |
| `scripts/verify.sh` | End-to-end checks; CI gates on its exit code |
| `steps/<step-id>/` | The commands and captured outputs each documented step shows |
| `tests/doc-detective/` | `_setup` and `_teardown`; the step specs are generated from the pages |

## Docs

The pages under `docs/modules/schema-registry-migration/` in the repository
read this directory through symlinks: `include::example$...` shows code from
here, and the build-along files are published as attachments. Change code
here and the docs follow.
