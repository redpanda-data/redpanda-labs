# Writing a Redpanda Solution

This is the canonical guide for the `solutions` component. It defines what a
Solution is, the metadata every Solution carries, the shape of its pages and
code, the verification bar, and the workflow from proposal to release. CI
enforces most of it; the rest is the review checklist at the end.

## What a Solution is

A Solution is an end-to-end, runnable reference architecture built on Redpanda
that solves one named business problem. A reader starts an environment, builds
the system step by step, verifies that it does what the docs claim, and leaves
knowing which Redpanda capabilities made the design work and what changes on
the path to production.

A Solution is not a feature how-to, a quickstart, or a code sample. Those live
in Product Docs. A Solution links to them and never re-explains them.

### Qualification checklist

A proposal qualifies when every item is true:

- [ ] It solves a business problem a reader recognizes ("a live leaderboard
      for a multiplayer game"), not a feature exercise ("try Data Transforms").
- [ ] It combines at least three Redpanda-adjacent components (for example
      brokers, Schema Registry, Redpanda Connect, Console, Tiered Storage, a
      client library, a sink such as Postgres or a lakehouse).
- [ ] The complete build-along path runs end to end in 60 minutes or less on a
      laptop with Docker Compose.
- [ ] `scripts/verify.sh` proves the outcome with exact assertions (counts,
      lags, sums), not "it started".
- [ ] It has a production path: every shortcut in the demo has a row in the
      Production considerations table with a link to the canonical guidance.
- [ ] The canonical Product Docs pages it depends on exist. If one is missing,
      file a DOC ticket first; do not write the concept into the Solution.

### What does not qualify, and where it goes

| Content | Where it belongs |
|---|---|
| A single feature walkthrough (one connector, one transform, one config) | Product Docs how-to or tutorial |
| A client library "hello world" in one language | Product Docs client tutorial with language tabs |
| A Docker Compose file with no application on top | Product Docs get-started page, compose file as an attachment |
| A Connect pipeline with a Bloblang mapping and nothing else | Redpanda Connect cookbook |
| An experiment with no production path | A blog post |

### The boundary rule

Ask of every paragraph: would this be true in any solution that uses the
feature? If yes, it is Product Docs. Link it. Keep only what is specific to
this problem and this design.

Examples:

- "A consumer group assigns each partition to exactly one member" is Product
  Docs. Link `streaming:develop:consume-data/consumer-offsets.adoc`.
- "The leaderboard and achievements services read `game.player-events` in two
  consumer groups so a slow achievements deploy never delays the leaderboard"
  is Solution content.
- "Enable schema ID validation with `redpanda.value.schema.id.validation`" is
  Product Docs. The Solution's Production considerations row says "enable
  schema ID validation on both topics" and links it.

## Layout of one Solution

```
solutions/<slug>/                      code, driven by make
  docker-compose.yml                   redpanda, console, rpk helper, your services
  .env.example                         pinned versions; copied to .env by make up
  Makefile                             up, down, seed, verify, logs, clean, test-docs
  scripts/verify.sh                    sources tools/verify-lib.sh; prints PASS (n/n)
  services/, connect/, proto/, ...     the actual system
  sample-data/                         deterministic seed data, committed
  tests/doc-detective/.doc-detective.json   beforeAny/afterAll over the shared base
  tests/doc-detective/specs/_setup.json, _teardown.json, <step-id>.json
  README.md                            how to run the code; what the bundle contains
docs/modules/<slug>/
  pages/index.adoc                     overview, all metadata
  pages/<step-id>.adoc                 one page per step
  images/architecture.svg
  partials/
  examples -> ../../../solutions/<slug>                      include::example$...
  attachments/{docker-compose.yml,env.example,Makefile.mk}   build-along files (symlinks)
  attachments/scripts/{verify.sh,verify-lib.sh}
```

`tools/new-solution.sh <slug>` creates all of it. The slug is the directory
name, the Antora module name, and the solution id. The slug rule (`SLUG_RE`)
and the reserved ids (`RESERVED_IDS`) are defined once in `tools/lib.sh`.

### The `examples` module is not a solution

`docs/modules/examples/` holds runnable code for Product Docs tutorials (the
chat-room clients, the data-transforms cookbook, the OIDC compose stack). A
Product Docs page includes it with `include::solutions:examples:example$...`
and readers get it as public attachment zips that the docs-site
`archive-attachments` extension builds. It has no pages, no metadata, and no
download gate. `tools/check-metadata.sh` and `tools/changed-solutions.sh`
skip it. See `docs/modules/examples/README.md`.

## Metadata reference

All metadata is authored once, on `docs/modules/<slug>/pages/index.adoc`.
Step pages carry only their own layout, description, and duration.
`tools/check-metadata.sh` validates the file; the `solutions-catalog` build
extension validates it again with the site context (resolving resource IDs,
checking categories against the shared list).

| Attribute | Required | Values | Notes |
|---|---|---|---|
| `:page-layout:` | yes | `solution` | `solution-step` on step pages |
| `:page-topic-type:` | yes | `solution` | |
| `:description:` | yes | one sentence, 200 chars or fewer | Card text, meta description, search snippet |
| `:page-solution-version:` | yes | `vX.Y.Z` | The only version input. Drives the tag `<slug>/<version>` and asset `<slug>-<version>.zip`. Released only when status is `published` or `deprecated`. Bump on any change a reader would notice. Keep each attribute on one line. |
| `:page-solution-difficulty:` | yes | `beginner`, `intermediate`, `advanced` | |
| `:page-solution-duration:` | yes | integer minutes, 5 to 600 | Whole build-along path; within 10% of the sum of the step durations |
| `:page-solution-status:` | yes | `draft`, `published`, `deprecated` | Drafts build only with `SOLUTIONS_INCLUDE_DRAFTS=true`. Deprecated publishes with a banner and leaves recommendations. |
| `:page-solution-featured:` | no | `true` | Featured on the landing page. Omit otherwise. |
| `:page-solution-download:` | yes | `authenticated`, `public`, `none` | Who can fetch the release bundle |
| `:page-solution-platforms:` | no | subset of `self-managed`, `cloud` | Default both. Filters recommendations on Cloud vs Self-Managed pages. |
| `:page-solution-technologies:` | yes | comma list | Chips on the card; search facet |
| `:page-categories:` | yes | comma list from `valid-categories.yml` | Unknown values fail the build. Parents are added automatically. |
| `:page-solution-use-cases:` | no | comma list | |
| `:personas:` | no | ids from `docs/modules/ROOT/partials/personas.yaml` | |
| `:page-solution-steps:` | yes | ordered comma list of step ids | The only source of step order. Each id is `pages/<id>.adoc` and `specs/<id>.json`. |
| `:page-solution-related-docs:` | recommended | fully qualified resource IDs | Must resolve. Warn when absent. These are the strongest "Build it in practice" edges on Product Docs. |
| `:page-solution-related-solutions:` | no | solution ids | |
| `:page-solution-superseded-by:` | when deprecated | solution id | |
| `:page-solution-step-duration:` | no (step pages) | integer minutes | |

Derived at build time, never authored: `page-solution-id`, `page-solution-repo`,
`page-solution-asset`, `page-solution-tag`, step navigation, and the
`page-solution` record the layouts render.

## Section structure

### Overview (`index.adoc`)

1. Title: the outcome, not the technology ("Multiplayer game events with a
   live leaderboard", not "Redpanda + Go + Redis").
2. Intro: two short paragraphs, 50 to 80 words in total. The first names the
   business problem; the second says what the reader builds and what they
   have running at the end.
3. "After completing this solution, you will be able to:" with three to five
   outcomes as literal checkboxes (`* [ ] ...`). Each one is observable.
   Solutions use these literal checkboxes, not `:learning-objective-N:`
   attributes.
4. `== What you build`: the running system in two or three sentences plus a
   bullet per component.
5. `== Architecture`: diagram (`images/architecture.svg`), a left-to-right walk
   of the diagram, and `=== Why Redpanda`: the capabilities the design depends
   on, each linked to its canonical page.
6. `== Prerequisites`: tools with versions, CPU and RAM, time. State that every
   step is completable without the download.
7. `== Production considerations`: a table with three columns (Area, In this
   solution, In production). Cover at least: brokers and replication, security,
   partitions, schema validation, consumer scaling, data retention, idempotency
   and delivery, dead-letter handling, observability, disaster recovery,
   analytics and lakehouse. Every "In production" cell links the canonical page.
8. `== Clean up`: `make clean`.
9. `== Related docs`: anything from `:page-solution-related-docs:` that needs a
   sentence of context.

The step list is rendered from `:page-solution-steps:`. Do not write it out.

### Step (`<step-id>.adoc`)

Title is an imperative verb phrase ("Register the schemas"). Then, in order:

- Intro, one or two sentences: what the reader does and why now.
- `== What you do`: numbered instructions with exact commands. Code from the
  repository is shown with `include::example$...[tags=...]`.
- `== Why`: the design decision in terms of the business problem.
- `== Why Redpanda`: the capability that makes this step simple, linked.
- `== What happens inside`: what the brokers, consumer groups, Schema Registry,
  or Connect do when the commands run. Only the behaviour this step exercises.
- Verification: either a `== Verify` section or a `[.solution-verify]` block,
  with one exact command and its expected output, then the one or two most
  likely failures and their fixes. This is what the step's Doc Detective spec
  replays. A published step must have one or the other.
- `== In production`: one or two sentences in a `[.production-note]` block,
  linking the Production considerations row or the canonical page.

Both `[.solution-verify]` and `[.production-note]` render as styled callouts
in the solution layouts.
- `.Files for this step`: the attachments a build-along reader needs.

## Verification standard

- `make up` waits for every healthcheck (`docker compose up -d --wait`). Every
  service in the compose file has a healthcheck. Run one stack at a time, or
  set different host ports in `.env` (`CONSOLE_PORT`, `REDPANDA_KAFKA_PORT`,
  and the other `*_PORT` variables from `.env.example`) for each.
- `make seed` is idempotent and deterministic. Seed data is committed under
  `sample-data/`; generated data comes from a service with a fixed seed and an
  event cap so counts are exact.
- `scripts/verify.sh` sources `tools/verify-lib.sh`, uses `assert_eq`,
  `assert_ge`, `assert_contains`, `assert_cmd`, and `retry`, and ends with
  `verify_summary`, which prints `PASS (n/n)` or lists the failed checks and
  prints `FAIL`. CI gates on its exit code. Every claim a step makes has a check:
  topic and partition counts, high watermarks against the event cap, consumer
  group lag 0, sink row counts equal to source counts, dead-letter topic empty,
  dashboards and `/ready` endpoints answering.
- The last step of every Solution runs `scripts/verify.sh` and shows its output.
- Versions are pinned in `.env.example` before a Solution is `published`. The
  nightly workflow overrides them with `latest` and opens an issue when a
  Solution breaks.

## Production checklist

Before a Solution goes `published`, every row of the Production considerations
table is filled and linked, and the code follows these conventions:

- Producers are idempotent; consumers commit after processing.
- Every topic has an explicit partition count and a stated key with its
  ordering guarantee.
- Anything that can fail has a dead-letter path and the docs show where the
  failures land.
- Secrets come from `.env`, never from the compose file or the docs.
- No `latest` image tag in `.env.example` when `published`.

## Linking and code inclusion

- Link Product Docs with fully qualified xrefs:
  `xref:streaming:develop:consume-data/consumer-offsets.adoc[]`,
  `xref:connect:components:outputs/sql_insert.adoc[]`,
  `xref:cloud:...`. Never a bare URL to docs.redpanda.com.
- Show code with `include::example$services/leaderboard/main.go[tags=consume]`.
  Mark regions in the source with `// tag::consume[]` and `// end::consume[]`
  (or the language's comment syntax). Never paste source into a page; the
  page and the code would drift.
- No `ifdef::env-github[]` or `ifdef::env-site[]` in `docs/`. The pages are
  written for the site only. The code directory has its own `README.md` for
  people who open the bundle.
- Never link to this repository, its files, or its releases from a page. The
  repository may be private; the download function and the attachments are
  the reader's paths to the code.
- Backtick every command, flag, file name, topic name, and `rpk` subcommand,
  in prose and in headings.

## Build-along rule

Every step must be completable with the page and the public attachments alone.
Every file a reader needs that is not shown in full on the page is an
attachment under `docs/modules/<slug>/attachments/` (a relative symlink into
`solutions/<slug>/`), listed in that step's `.Files for this step`. The
signed-in download of the complete bundle is a shortcut, never a prerequisite.
The reviewer checks this by completing step 1 from the attachments alone.

Antora silently drops dotfiles and files without an extension, so publish
`.env.example` as `env.example` and `Makefile` as `Makefile.mk` and tell the
reader what to save them as. `tools/check-metadata.sh` fails on any attachment
Antora would skip.

## Doc Detective

Every step has a standalone spec `solutions/<slug>/tests/doc-detective/specs/<step-id>.json`
that replays the step's Verify section (and the commands that lead to it) as
`runShell` steps with `stdio` expectations. Specs are JSON files, never inline
`// (step ...)` comments in the page.

- `_setup.json` (`make up`, `make seed`) runs once before the step specs
  (`beforeAny`), `_teardown.json` (`make clean`) once after (`afterAll`). They
  are not steps and are never listed in `:page-solution-steps:`.
- `tools/run-doc-detective.sh <slug>` merges `tools/doc-detective.base.json`
  with the solution's `.doc-detective.json` and runs the spec of every listed
  step. `make test-docs` calls it.
- Prefix resources a spec creates with the solution slug so specs never
  collide. Never put credentials in a spec.

## Review checklist

- [ ] `tools/check-metadata.sh` exits 0 with no warnings that matter.
- [ ] Title and intro state the business problem; outcomes are observable.
- [ ] Every paragraph passes the boundary rule; concepts are linked, not
      re-explained.
- [ ] Architecture diagram matches the compose file (same services, same
      topics).
- [ ] Every "In production" cell links a canonical page.
- [ ] Step 1 completes from the page and attachments alone (reviewer tries it).
- [ ] Every Verify section has an exact command and exact expected output, and
      its spec replays it.
- [ ] `make up seed verify` prints `PASS (n/n)` on a clean machine.
- [ ] No pasted code; every include has a tagged region.
- [ ] No repository links, no GitHub or site conditionals under `docs/`.
- [ ] `.env.example` pins versions; `:page-solution-version:` bumped if
      anything a reader notices changed.
- [ ] Backticked commands and `rpk` subcommands; no em dashes; plain sentences.

## Workflow

1. Proposal: open an issue with the business problem, the components, the
   step list, the Product Docs pages you will link, and which qualification
   items are risky. Get a thumbs up from `@redpanda-data/docs`.
2. Scaffold: `tools/new-solution.sh <slug>`. Commit the scaffold on a branch.
3. Build it as `draft`: code first, `make verify` green, then pages. Run
   `tools/check-metadata.sh` and `npm run build` locally (see "Build the docs
   locally"). Open a PR; `ci` and `docs` must pass.
4. Review against the checklist above. Preview the pages on the docs-site
   deploy preview (drafts render there).
5. Publish: set `:page-solution-status: published`, set
   `:page-solution-version: v1.0.0`, pin versions in `.env.example`, merge.
   Drafts are never released, so this is the first release: the workflow
   creates the release `<slug>/v1.0.0` (which creates the tag) with
   `<slug>-v1.0.0.zip`, then posts the site build hook. Any version already
   released is left alone, so a re-run is safe.
6. Change: bump the version on any reader-visible change; the next merge
   releases it. Fixes that change nothing a reader sees do not need a bump.
7. Deprecate: set `deprecated` and `:page-solution-superseded-by:`. The page
   stays with a banner and leaves recommendations.
8. Retire: delete `solutions/<slug>/` and `docs/modules/<slug>/` and add a
   `:page-aliases:` entry on the receiving page (or a redirect in docs-site).

## Build the docs locally

The local playbook aggregates the private `docs`, `cloud-docs`, and
`rp-connect-docs` repositories so xrefs resolve. Antora ignores git
credential helpers, so store a token once:

```bash
echo "https://$(gh auth token):@github.com" >> ~/.git-credentials
chmod 600 ~/.git-credentials
npm ci
SOLUTIONS_INCLUDE_DRAFTS=true npm run build
npm run serve
```

`npm run build` uses `tools/local-antora-playbook.yml`, which builds both the
`solutions` component and the frozen `labs` component from this repository.

## Labs content

`labs-docs/` and the legacy code directories (`docker-compose/`, `clients/`,
`data-transforms/`, `kubernetes/`, `connect-plugins/`, `setup-tests/`) are the
retired Redpanda Labs, frozen until each lab is promoted into a Solution,
extracted into Product Docs, or retired with a redirect. Do not edit them.
