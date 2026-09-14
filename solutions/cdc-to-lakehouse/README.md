# CDC to lakehouse

Code for the CDC to lakehouse solution. The guided walkthrough lives on the
docs site at `/solutions/cdc-to-lakehouse/`; this directory is what `make`
drives and what the download bundle contains.

Postgres and MySQL are the operational databases. Redpanda Connect reads their
change logs and writes one shaped event per row change to the `cdc_orders`
topic. That topic is Iceberg-enabled, so Redpanda writes the Parquet and
metadata files into MinIO and registers the table with the Iceberg REST
catalog. Spark queries the table through the same catalog.

## Before you start

The `postgres_cdc` and `mysql_cdc` inputs are enterprise components of
Redpanda Connect. A new Redpanda cluster starts a 30-day trial license for
itself, which covers Iceberg topics and Tiered Storage, but Redpanda Connect
reads its license from the environment. Put a trial or Enterprise Edition
license key in `REDPANDA_LICENSE` in `.env` before you run the change data
capture targets. Everything else runs without a key.

## Run it

```bash
make up            # build the Spark image, start the stack, wait for every healthcheck
make seed          # create the Iceberg topic and register its schema
make cdc-postgres  # start the Postgres change data capture pipeline
make changes       # one insert, one update, one delete
make query-changes # read the change log out of the lakehouse with Spark
make verify        # prints PASS (n/n) when the system does what the docs claim
make clean         # stop and delete volumes
```

`make help` lists every target. Versions, ports, and credentials are in `.env`
(copied from `.env.example` on the first `make up`).

## Layout

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Redpanda, MinIO, the Iceberg REST catalog, Postgres, MySQL, Spark, Console, an `rpk` helper, and the two profile-gated Redpanda Connect pipelines |
| `Makefile` | The `up`, `down`, `seed`, `verify`, `logs`, `clean`, `test-docs` contract plus the pipeline and query targets |
| `connect/postgres-cdc.yaml`, `connect/mysql-cdc.yaml` | The two change data capture pipelines |
| `postgres/init.sql`, `mysql/init.sql` | The operational schema and its seed rows |
| `schemas/order-change.json` | The JSON schema that gives the Iceberg table its columns |
| `sql/queries.sql` | The Spark SQL queries, one tagged region each |
| `spark/` | A plain Apache Spark image plus the two Iceberg jars |
| `scripts/verify.sh` | End-to-end checks; CI gates on its exit code |
| `scripts/change-orders.sh`, `scripts/lakehouse.sh` | Apply row changes; run the queries |
| `tests/doc-detective/` | `_setup` and `_teardown`; the step specs are generated |

## Docs

The pages under `docs/modules/cdc-to-lakehouse/` in the repository read this
directory through symlinks: `include::example$...` shows code from here, and
the build-along files are published as attachments. Change code here and the
docs follow.
