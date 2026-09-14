# Migration note: four labs to one solution

This solution expands and merges four Redpanda Labs labs:

| Lab | Published at | Source page | Class |
|---|---|---|---|
| `docker-compose/cdc/postgres-json` | `/labs/docker-compose/cdc-postgres-json/` | `labs-docs/modules/docker-compose/pages/cdc-postgres-json.adoc` | Expand (primary) |
| `docker-compose/cdc/mysql-json` | `/labs/docker-compose/cdc-mysql-json/` | `labs-docs/modules/docker-compose/pages/cdc-mysql-json.adoc` | Merge (alternative source step) |
| `docker-compose/iceberg` | `/labs/docker-compose/iceberg/` | `labs-docs/modules/docker-compose/pages/iceberg.adoc` | Merge (Iceberg topics, MinIO, Spark) |
| `kubernetes/iceberg` | `/labs/kubernetes/iceberg/` | `labs-docs/modules/kubernetes/pages/iceberg.adoc` | Merge (folded into Production considerations) |

The four lab directories are left untouched, and the labs pages keep building
from them until the decommission wave. This solution was built from copies,
rewritten to the solution contract.

## Kept

From `cdc/postgres-json` and `cdc/mysql-json`:

- The business shape: a `pandashop` database with one `orders` table, seeded
  with a handful of rows, and the insert that proves the pipeline end to end.
  The insert became an insert, an update, and a delete, because a change log
  that only ever appends is not a change log.
- The column set (`order_id`, `customer_id`, `total`, `created_at`), with
  `status` added so an update has something to change.
- The MySQL binary log settings (`server-id`, `log-bin`, `binlog-format=ROW`)
  from `data/mysql.cnf`, moved onto the server command line, and the MySQL
  replication grants from `data/mysql_bootstrap.sql`.

From `docker-compose/iceberg`:

- The architecture: Redpanda with Tiered Storage backed by MinIO, an Iceberg
  REST catalog, Iceberg-enabled topics (`redpanda.iceberg.mode`), and Spark
  reading the tables through the catalog.
- The MinIO and `mc` services, including the `<bucket>.minio` network alias
  that makes Redpanda's virtual-host style bucket URL resolve inside the
  compose network, and the bucket bootstrap.
- The Iceberg cluster properties, including the lowered
  `iceberg_catalog_commit_interval_ms` and `iceberg_target_lag_ms` with the
  note that production leaves both at their defaults.
- The Spark catalog wiring from `spark/spark-defaults.conf` (see Provenance).

From `kubernetes/iceberg`:

- The operational lessons, as Production considerations rows: the MinIO
  Operator tenant instead of a single container, the Iceberg REST catalog's
  DNS resolution problem behind bucket-style S3 URLs, the NodePort workaround
  for the MinIO console's websockets, and the Redpanda Operator deployment
  path. The manifests stay in `kubernetes/iceberg/` and are not copied here.

## Rewritten

- **Debezium is gone.** Both CDC labs ran Debezium on Kafka Connect: a JVM
  container, three internal Kafka Connect topics, a REST call with a JSON
  connector configuration embedded in the page, and one topic per table named
  by the connector's `topic.prefix`. This solution uses Redpanda Connect's
  `postgres_cdc` and `mysql_cdc` inputs, which read the write-ahead log and
  the binary log directly. The Debezium route is one paragraph on the overview
  for readers who already run Kafka Connect.
- **The events are shaped, not raw.** The labs published Debezium's envelope
  (`before`, `after`, `source`, `op`) straight to the topic. Here a Bloblang
  mapping turns each change into one flat row with `op`, `source`,
  `order_id`, `customer_id`, `total`, `status`, `created_at`, `position`, and
  `captured_at`, which is what makes the Iceberg table queryable without
  unpacking JSON in SQL.
- **The lakehouse is the destination, not a separate lab.** The Iceberg lab
  produced `hello world` and three hand-written click events with
  `rpk topic produce`. Here the topic's rows are real database changes, and
  the table's columns come from a registered JSON schema.
- **`value_schema_latest` instead of `value_schema_id_prefix`.** The Iceberg
  lab used `value_schema_id_prefix`, which needs every producer to frame its
  records in the Schema Registry wire format. `value_schema_latest` with a
  JSON schema takes the records as they are, so the Connect pipeline writes
  plain JSON and Redpanda maps it onto the table's columns. It needs Redpanda
  v25.2 or later.
- **Spark SQL instead of a Jupyter notebook.** The lab's notebook
  (`spark/notebooks/Iceberg - Query Redpanda Table.ipynb`) cannot be tested.
  The queries now live in `sql/queries.sql` as tagged regions, run through
  `docker compose exec spark spark-sql`, and the pages include the regions.
- **A 4 GB Spark image became a small one.** The lab's `spark/Dockerfile`
  built Spark from a tarball and added Jupyter, `spylon-kernel`, the IJava
  kernel, `pyiceberg`, `matplotlib`, `scipy`, DuckDB, the AWS CLI, and 14 New
  York taxi Parquet files downloaded at build time (the Kubernetes lab's own
  README records the result as 3.83 GB). This solution's image is
  `apache/spark` plus two Iceberg jars, and the Spark driver is capped at
  1 GB.
- **Ports moved so the stack runs next to the other solutions**: Console
  `8480`, Redpanda Kafka `64092`, Schema Registry `64081`, Admin API `64644`,
  Postgres `5433`, MySQL `3307`, MinIO `9100` and `9101`, Iceberg REST
  `8581`, Spark UI `4041`, Redpanda Connect `4196`, all overridable in
  `.env`. The brief for this migration asked for Kafka on `79092` and Schema
  Registry on `78081`; both are above the highest TCP port, 65535, so the
  distinct block moved to `64xxx`.
- Container names are prefixed with the slug; the compose project is named;
  every service has a healthcheck and `make up` waits for all of them. The
  labs had healthchecks on two services and told the reader to wait "a minute
  or two".
- Credentials come from `.env`, never from a page. The labs put
  `postgresuser`/`postgrespw`, `debezium`/`dbz`, and `minio`/`minio123` in
  prose and in connector configurations.
- Everything is driven by `make` targets; the walkthrough is seven step pages
  with generated Doc Detective specs and captured expected outputs instead of
  two READMEs with no tests.

## Added

- `scripts/verify.sh`: the three counts that have to agree (the rows the
  database holds after the changes, the change events in the topic, and the
  rows in the Iceberg table), plus the per-operation breakdown, the
  reconstruction of current state from the change log, and the check that
  Redpanda created no `cdc_orders~dlq` dead-letter table.
- One Iceberg table fed by two databases: the MySQL pipeline writes to the
  same topic with `source: "mysql"`, so the alternative source step adds rows
  to the table the reader already queried instead of standing up a second
  stack.
- `REPLICA IDENTITY FULL` on the Postgres table, so a delete event carries the
  values the row held instead of just its primary key.
- A dead-letter path (`redpanda.iceberg.invalid.record.action=dlq_table`, the
  default, set explicitly) and the page text that says where failures land.
- Production considerations, an architecture diagram, and a Console
  screenshot captured by the test run.
- The licensing facts: the broker's automatic 30-day trial covers Iceberg
  topics and Tiered Storage, and Redpanda Connect needs its own key in
  `REDPANDA_LICENSE` because `postgres_cdc` and `mysql_cdc` are enterprise
  components.

## Dropped

- The Apache Software Foundation license header the Iceberg lab's
  `README.adoc` carried, and the lab's copy of the Apache License 2.0
  (`docker-compose/iceberg/LICENSE`). See Provenance for what remains and how
  it is attributed.
- The `git clone` instructions and the GitHub repository links (the solutions
  repository is private; readers use the attachments or the signed-in
  download).
- `ifdef::env-site`/`env-github` conditionals, the `:latest-redpanda-version:`
  attribute dance, and the "Next steps" bullet lists.
- Jupyter, the four notebook kernels, `pyiceberg`, DuckDB, `matplotlib`, the
  taxi datasets, the Spark master, worker, history server, and thrift server,
  and the `spark-shell` and `pyspark` alternatives. One `spark-sql` entry
  point is enough to run a query.
- The `key_value` Iceberg mode demonstration. It produces a table with one
  binary column, which is the opposite of what this solution is about; the
  mode is named in the overview and linked.
- `.pyiceberg.yaml`, which the Iceberg lab shipped with credentials
  (`admin`/`password`) that matched nothing in the stack and a catalog URI
  (`http://rest:8181`) that matched no service. It was dead configuration.

## Provenance of copied Apache material

- `spark/spark-defaults.conf` is adapted from the Apache Iceberg project's
  `docker-spark-image` example, which the Redpanda Labs Iceberg lab copied
  verbatim along with the Apache License 2.0 header. The Apache Iceberg
  project is licensed under the Apache License 2.0. What survives is the shape
  of the catalog configuration: the `spark.sql.extensions` class name, the
  `SparkCatalog` and `S3FileIO` class names, and the `type`, `uri`,
  `warehouse`, and `s3.endpoint` keys. The catalog is renamed to `lakehouse`,
  `cache-enabled` is off for a different reason (Redpanda commits a new
  snapshot every few seconds), path-style S3 access is added for MinIO, the
  event log and history server settings are dropped, and the driver memory
  cap is new. Those class names and keys are the Iceberg Spark runtime's
  public API, not creative expression, so the file no longer carries the ASF
  header.
- `spark/Dockerfile` shares no lines with the lab's Dockerfile. It is
  `FROM apache/spark` plus two `curl` commands for jars from Maven Central.
  The two Maven coordinates (`iceberg-spark-runtime-3.5_2.12` and
  `iceberg-aws-bundle`) came from the lab, which took them from the same
  Apache example.
- The MinIO service definition, the `mc` bucket bootstrap, and the
  `<bucket>.minio` network alias came from the Redpanda Labs Iceberg lab,
  which is Redpanda's own work. MinIO's own images are used unmodified.
- MinIO's images are pulled from `quay.io/minio/...`, not `minio/...`. The
  lab's Docker Hub references no longer resolve: that repository is gone, and
  `minio/minio:latest` is not pullable any more.
- `apache/iceberg-rest-fixture` replaces `tabulario/iceberg-rest`, which the
  lab used unpinned. The fixture image is the Apache Iceberg project's own
  build of the same REST catalog and takes the same `CATALOG_*` environment
  variables. It is used unmodified, as a container image.
- No Debezium code or configuration is carried over.

## What is verified, and what is not

Everything in this solution except the two change data capture inputs has been
run: the stack comes up with nine healthy services, the Iceberg topic and its
JSON schema are created, Redpanda lays out the table and writes Parquet into
MinIO, the REST catalog holds the table, and every query in `sql/queries.sql`
returns what the pages say it returns. `scripts/verify.sh` prints
`PASS (22/22)` against the documented event stream.

That run fed the topic with `rpk topic produce`, in the exact shape
`connect/postgres-cdc.yaml` emits, because `postgres_cdc` and `mysql_cdc` are
enterprise components and Redpanda Connect found no license:

```
level=error msg="service closing due to: failed to init input 'orders_cdc'
path root.input: this feature requires a valid Redpanda Enterprise Edition
license that includes the Connect product."
```

The broker's own 30-day trial license does not help: it is the cluster's, and
Redpanda Connect reads its license from `REDPANDA_LICENSE` and starts no trial
of its own. So the capture half is verified as far as it can be without a key
(both pipelines pass `connect lint`, and the Bloblang mapping was run against
the row shapes Postgres reports, including a delete that carries only the
primary key), and the expected outputs for `capture-postgres-changes`,
`shape-events`, `query-with-spark`, `capture-mysql-changes`, and
`verify-end-to-end` are not captured yet. Put a trial or Enterprise Edition
key in `REDPANDA_LICENSE` in `.env`, then run
`tools/capture-expected.sh cdc-to-lakehouse` on a clean stack followed by
`tools/run-doc-detective.sh cdc-to-lakehouse`, and the solution is complete.

## Aliases and redirects at decommission

All four labs redirect into this solution. Add these to
`docs/modules/cdc-to-lakehouse/pages/index.adoc` once the labs pages are out
of the build (Antora throws while a page and an alias to it both exist):

```
:page-aliases: labs:docker-compose:cdc-postgres-json.adoc, \
labs:docker-compose:cdc-mysql-json.adoc, \
labs:docker-compose:iceberg.adoc, \
labs:kubernetes:iceberg.adoc
```

`netlify.toml` rules, most specific first, so the per-page rules win before
the `/labs/*` catch-all:

| From | To |
|---|---|
| `/labs/docker-compose/cdc-postgres-json/` | `/solutions/cdc-to-lakehouse/` |
| `/labs/docker-compose/cdc-mysql-json/` | `/solutions/cdc-to-lakehouse/capture-mysql-changes/` |
| `/labs/docker-compose/iceberg/` | `/solutions/cdc-to-lakehouse/enable-iceberg-topics/` |
| `/labs/kubernetes/iceberg/` | `/solutions/cdc-to-lakehouse/` |

`docker-compose/cdc/README.adoc` has no `labs-docs` page symlink, so it never
published and needs no redirect. The `/redpanda-labs/...` twins of the four
URLs above redirect the same way, and all eight go in
`docs-site/solutions/labs-urls.txt` for
`docs-site/scripts/solutions/check-redirects.mjs`.

Then delete `docker-compose/cdc/`, `docker-compose/iceberg/`,
`kubernetes/iceberg/`, and the four `labs-docs` page symlinks
(`docker-compose/pages/cdc-postgres-json.adoc`,
`docker-compose/pages/cdc-mysql-json.adoc`,
`docker-compose/pages/iceberg.adoc`, `kubernetes/pages/iceberg.adoc`).
