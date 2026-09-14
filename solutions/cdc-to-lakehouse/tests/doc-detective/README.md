# Doc Detective specs

The step specs are generated, not committed. `tools/run-doc-detective.sh
cdc-to-lakehouse` at the repository root runs `tools/gen-dd-specs.mjs`, which
turns every step page into one spec: one `runShell` per command block the page
shows (`include::example$steps/<step-id>/commands.sh[tag=...]`), in page order,
plus a stdout check for every captured expected output the page includes right
after a command. The only files here are `_setup.json` (`make up`, run once
before the step specs) and `_teardown.json` (`make clean`, once after).
`make test-docs` calls the runner.

`tools/capture-expected.sh cdc-to-lakehouse` writes the expected outputs under
`steps/<step-id>/expected/` from a fresh stack (`make clean && make up`); run
it after changing behaviour and review the diff.

The steps are a sequence, and they only make sense in `:page-solution-steps:`
order from a clean stack: the Iceberg topic has to exist before the first
change event arrives, because Redpanda translates a topic's records to Iceberg
from the point the topic property is set, and `scripts/change-orders.sh` is
what makes the insert, update, and delete counts exact.

Two things about a run:

- The change data capture steps need a Redpanda Connect enterprise license in
  `REDPANDA_LICENSE` in `.env`. `postgres_cdc` and `mysql_cdc` are enterprise
  components, and unlike the broker's own 30-day trial, Redpanda Connect does
  not start one for itself. Without a key, `make cdc-postgres` stops with a
  message and the run fails at the `capture-postgres-changes` step.
- Every Spark query starts a driver, which takes a few seconds, so the
  `query-with-spark` and `verify-end-to-end` specs are the slow ones.

The `enable-iceberg-topics` step takes the one screenshot
(`steps/enable-iceberg-topics/media.json`): the Console topic view showing the
topic's Iceberg configuration. Nothing in this solution's browser views
changes on its own, so there is no recording.
