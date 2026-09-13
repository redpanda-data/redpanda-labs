# Doc Detective specs

One spec per documented step, named after the step id, plus `_setup.json`
(`make up`, run once before the step specs) and `_teardown.json` (`make
clean`, once after). `tools/run-doc-detective.sh multiplayer-gaming` at the
repository root merges `.doc-detective.json` over the shared base config and
runs the specs in step order; `make test-docs` calls it.

Everything the specs run is the local path: the `local` compose profile with
the `redpanda` and `console` containers, and the default `.env`. The
"Redpanda Cloud Serverless" tab in step 1 (`start-environment`) is not
covered by CI: it needs a cluster, a SCRAM user, and credentials that a spec
must never carry. Test it by hand from the tab's instructions when the
connection code (`services/internal/conn`, the `x-redpanda-env` block in
`docker-compose.yml`, `connect/match-history.yaml`) changes. The Tiered
Storage extension (`make tiered-up`) is likewise outside the specs; the
overview page shows the commands that prove it.
