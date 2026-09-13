# Doc Detective specs

The step specs are generated, not committed. `tools/run-doc-detective.sh
schema-registry-migration` at the repository root runs `tools/gen-dd-specs.mjs`,
which turns every step page into one spec: one `runShell` per command block
the page shows (`include::example$steps/<step-id>/commands.sh[tag=...]`), in
page order, plus a stdout check for every captured expected output the page
includes right after a command. The only files here are `_setup.json` (`make
up`, run once before the step specs) and `_teardown.json` (`make clean`, once
after). `make test-docs` calls the runner.

`tools/capture-expected.sh schema-registry-migration` writes the expected
outputs under `steps/<step-id>/expected/` from a fresh stack (`make clean &&
make up`); run it after changing behaviour and review the diff.

The steps are a sequence: the cut-over step pauses schema replication and
fails the topics over, which cannot be undone, so the specs only make sense
in `:page-solution-steps:` order from a clean stack. Two command blocks on the
cut-over page are marked `[.manual]` and are not run: the interactive
`rpk shadow update` (it opens an editor) and `make resume`, which would put
the write block back on the registry after the topics have already been
failed over. The `replicate-complex-schemas` step takes two Console
screenshots (`steps/replicate-complex-schemas/media.json`); nothing in this
solution's browser views changes on its own, so there is no recording.
