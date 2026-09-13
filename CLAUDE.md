# Redpanda Solutions

This repository owns the `solutions` Antora component (published at
`/solutions/`) and the runnable code behind every solution. CONTRIBUTING.md is
the canonical writer guide; this file is the short operating manual.

## Layout

```
docs/antora.yml                          component descriptor (name: solutions)
docs/modules/ROOT/pages/index.adoc       landing page (cards render from the catalog)
docs/modules/ROOT/partials/personas.yaml persona ids for :personas:
docs/modules/ROOT/partials/relationships.yml  editor-approved doc <-> solution edges
docs/modules/<slug>/pages/index.adoc     overview: all metadata lives here
docs/modules/<slug>/pages/<step-id>.adoc one page per step
docs/modules/<slug>/examples             symlink -> ../../../solutions/<slug>
docs/modules/<slug>/attachments/*        symlinks to the build-along files (env.example, Makefile.mk:
                                         Antora drops dotfiles and extension-less files)
solutions/<slug>/                        docker-compose.yml, Makefile, .env.example,
                                         services, scripts/verify.sh,
                                         tests/doc-detective/{.doc-detective.json,specs/}
tools/                                   shared harness (see below)
templates/solution/                      scaffold copied by tools/new-solution.sh
labs-docs/, docker-compose/, clients/, data-transforms/, kubernetes/,
connect-plugins/, setup-tests/           frozen labs content awaiting migration
```

## The contract

- Slug = directory = module = solution id. Reserved: `progress`, `download`,
  `api`, `index`, `ROOT`.
- Every attribute on the overview page is part of the contract
  (CONTRIBUTING.md, "Metadata reference"). `:page-solution-steps:` is the only
  source of step order; there is no nav.adoc.
- Each step id has `pages/<id>.adoc` (`:page-layout: solution-step`) and
  `solutions/<slug>/tests/doc-detective/specs/<id>.json`, and every non-index
  page is a step. `tools/check-metadata.sh` enforces this.
- `:page-solution-version:` (vX.Y.Z) is the only version input. On merge to
  main the release workflow tags `<slug>/<version>` and publishes
  `<slug>-<version>.zip` if that tag does not exist yet.
- `:page-solution-status:` is `draft` until the solution is reviewed. Drafts
  build only when `SOLUTIONS_INCLUDE_DRAFTS=true`.

## Build-along rule

The repository may be private. Every file a reader needs that is not shown in
full on a page must be published as an attachment
(`docs/modules/<slug>/attachments/`), and every step must be completable from
the page plus attachments. The signed-in download is a shortcut, never a
prerequisite. Never link to this repository from a page.

Show code with `include::example$<path>[tags=<region>]` from the `examples`
symlink. Never paste source into a page. No `ifdef::env-github[]` or
`env-site` conditionals under `docs/`.

## Copy a sibling

Do not design a solution's files from scratch. Run
`tools/new-solution.sh <slug>` for a new one, or copy the closest existing
solution and change what differs. The Makefile targets (`up`, `down`, `seed`,
`verify`, `logs`, `clean`, `test-docs`), the `rpk` helper container, the
`verify.sh` shape (`PASS (n/n)`), and the `_setup`/`_teardown` spec split are
the same in every solution on purpose.

## Commands

```bash
tools/new-solution.sh <slug>        scaffold code + docs module + symlinks
tools/check-metadata.sh [<slug>]    metadata contract; run before every PR
tools/changed-solutions.sh [base]   JSON matrix of touched slugs (--all for every slug)
tools/run-doc-detective.sh <slug>   Doc Detective specs for one solution
npm run build && npm run serve      Antora build (needs ~/.git-credentials)
cd solutions/<slug> && make up seed verify && make clean
```

Verification is execution: a change is done when `check-metadata.sh` exits 0,
`make verify` prints `PASS`, and `npm run build` succeeds. Do not infer a
pass from reading code.

## Style

Plain, direct prose. No em dashes. Backtick every command, flag, file name,
topic name, and `rpk` subcommand. Headings are imperative for steps
("Start the environment") and nouns for overview sections.
