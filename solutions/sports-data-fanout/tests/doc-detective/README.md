# Doc Detective specs

The step specs are generated, not committed. `tools/run-doc-detective.sh
sports-data-fanout` at the repository root runs `tools/gen-dd-specs.mjs`,
which turns every step page into one spec: one `runShell` per command block
the page shows (`include::example$steps/<step-id>/commands.sh[tag=...]`), in
page order, plus a stdout check for every captured expected output the page
includes right after a command. The only files here are `_setup.json` (`make
up`, run once before the step specs) and `_teardown.json` (`make clean`, once
after). `make test-docs` calls the runner.

`tools/capture-expected.sh sports-data-fanout` writes the expected outputs
under `steps/<step-id>/expected/` from a fresh stack (`make clean && make
up`); run it after changing behaviour and review the diff.

Everything the specs run is the local path: the `local` compose profile with
the `redpanda` and `console` containers, and the default `.env`. Two things
are not covered by CI: the "Redpanda Cloud Serverless" tab in step 1 (it
needs a cluster, a SCRAM user, and credentials a page must never carry; its
`.env` fragment is `env.cloud.example`), and `make proto` in step 1, which is
marked `[.manual]` because only a build-along reader needs it. The Tiered
Storage extension on the overview (`make tiered-up`) is proven by hand; the
overview is not a step. Test the Cloud path by hand from the tab's
instructions when the connection code (`services/internal/conn`, the
`x-redpanda-env` block in `docker-compose.yml`, `connect/match-history.yaml`)
changes.
