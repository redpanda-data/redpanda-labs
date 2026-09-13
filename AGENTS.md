# Agent guide

Short version of CLAUDE.md for other tools. Read CONTRIBUTING.md before
changing content.

- One solution = `solutions/<slug>/` (code) + `docs/modules/<slug>/` (pages).
  The slug is the directory, the Antora module, and the solution id.
- Never write a solution from scratch: run `tools/new-solution.sh <slug>` or
  copy a sibling solution.
- The docs read code through symlinks: `include::example$<path>[tags=...]`,
  never pasted source. Build-along files are attachments; every step must be
  completable without the download.
- Metadata is the contract: `tools/check-metadata.sh` must pass. Every step id
  in `:page-solution-steps:` has `pages/<id>.adoc` and
  `tests/doc-detective/specs/<id>.json`.
- Prove it: `make up seed verify` prints `PASS (n/n)`. CI gates on the exit
  code of `scripts/verify.sh`, `tools/check-metadata.sh`, and `npm run build`.
- `docs/modules/examples/` is not a solution: it holds ungated code for
  Product Docs tutorials (see its README.md). Tools skip it.
- `labs-docs/` and the legacy directories (`docker-compose/`, `clients/`,
  `data-transforms/`, `kubernetes/`, `connect-plugins/`, `setup-tests/`) are
  frozen. Do not edit them; migrate a lab into `solutions/<slug>/` instead.
- No em dashes in prose. Plain, direct sentences.
