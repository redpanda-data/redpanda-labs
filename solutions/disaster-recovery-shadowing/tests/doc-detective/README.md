# Doc Detective

`tools/run-doc-detective.sh disaster-recovery-shadowing` (or `make test-docs`)
generates one spec per step from the step pages and runs them in
`:page-solution-steps:` order. The generated specs are never committed:
`tools/gen-dd-specs.mjs` reads every command block and every expected-output
include from the pages themselves, so a command that is not on a page is not
tested and a command on a page cannot drift from the tested one.

The two specs here are the exceptions, because they are not steps:

| Spec | When | What |
|---|---|---|
| `_setup.json` | `beforeAny` | `make up` |
| `_teardown.json` | `afterAll` | `make clean` |

Nothing is seeded in `_setup`. The walkthrough is the test: the step specs
create the topic and the link, produce and consume through Envoy, stop the
source cluster, fail the link over, and run `scripts/verify.sh`, in that
order, so a run proves the documented order works and not just the commands.

The `deploy-on-kubernetes` step is the one step that is mostly not run. Its
manifest check runs on every pass; every command that needs a Kubernetes
cluster carries the `[.manual]` role on the page and is skipped, because a
kind cluster running the Redpanda Operator and two Redpanda clusters does not
fit alongside the compose stack the earlier steps leave running. `MIGRATION.md`
records that decision.

Two steps also carry a `media.json`: the screenshots the pages show are taken
by the run, against the shadow cluster's Redpanda Console, and are never
edited by hand.
