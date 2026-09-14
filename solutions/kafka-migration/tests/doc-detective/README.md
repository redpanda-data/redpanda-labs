# Doc Detective specs

The step specs are generated, not committed. `tools/run-doc-detective.sh
kafka-migration` at the repository root runs `tools/gen-dd-specs.mjs`, which
turns every step page into one spec: one `runShell` per command block the
page shows (`include::example$steps/<step-id>/commands.sh[tag=...]`), in page
order, plus a stdout check for every captured expected output the page
includes right after a command. The only files here are `_setup.json` (`make
up`, run once before the step specs) and `_teardown.json` (`make clean`, once
after). `make test-docs` calls the runner.

`tools/capture-expected.sh kafka-migration` writes the expected outputs under
`steps/<step-id>/expected/` from a fresh stack (`make clean && make up`); run
it after changing behaviour and review the diff.

Everything the specs run is the local two-cluster path with the default
`.env`. The Console screenshots the pages show are taken by the same run
(`steps/<step-id>/media.json`).
