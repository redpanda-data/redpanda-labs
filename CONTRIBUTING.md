# Writing a Redpanda Solution

This is the canonical guide for the `solutions` component. It defines what a
solution is, the metadata every solution carries, the shape of its pages and
code, the verification bar, and the workflow from proposal to release. CI
enforces most of it; the rest is the review checklist at the end.

## What a solution is

A solution is an end-to-end, runnable reference architecture built on Redpanda
that solves one named business problem. A reader starts an environment, builds
the system step by step, verifies that it does what the docs claim, and leaves
knowing which Redpanda capabilities made the design work and what changes on
the path to production.

A solution is not a feature how-to, a quickstart, or a code sample. Those live
in Product Docs. A solution links to them and never re-explains them.

Terminology: write "solution" in lowercase in prose. "Redpanda Solutions" is
the name of the section and the only capitalized form.

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
      file a DOC ticket first; do not write the concept into the solution.

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
  is solution content.
- "Enable schema ID validation with `redpanda.value.schema.id.validation`" is
  Product Docs. The solution's Production considerations row says "enable
  schema ID validation on both topics" and links it.

## Layout of one solution

```
solutions/<slug>/                      code, driven by make
  docker-compose.yml                   redpanda, console, rpk helper, your services
  .env.example                         pinned versions; copied to .env by make up
  Makefile                             up, down, seed, verify, logs, clean, test-docs
  scripts/verify.sh                    sources tools/verify-lib.sh; prints PASS (n/n)
  services/, connect/, proto/, ...     the actual system
  sample-data/                         deterministic seed data, committed
  steps/<step-id>/commands.sh          every command the step page shows, tagged
  steps/<step-id>/expected/<name>.txt  captured stdout of a command block
  steps/overview/commands.sh           commands the overview shows (Clean up, extensions)
  tests/doc-detective/.doc-detective.json   beforeAny/afterAll over the shared base
  tests/doc-detective/specs/_setup.json, _teardown.json   (step specs are generated)
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
| `:page-solution-difficulty:` | yes | `beginner`, `intermediate`, `advanced` | What the reader must bring, not how deep the material goes. See "Difficulty and assumed knowledge". The landing page filters on it. |
| `:page-solution-assumes:` | no | comma list of 1 to 4 short phrases | What the reader should already know, in their words, not ids or xrefs: `Docker, topics, reading Go`. Renders beside the difficulty chip. With difficulty, this is what readers use to choose a solution. Warn when a `published` solution has none. |
| `:page-solution-duration:` | yes | integer minutes, 5 to 600 | Whole build-along path; within 10% of the sum of the step durations |
| `:page-solution-status:` | yes | `draft`, `published`, `deprecated` | Drafts build only with `SOLUTIONS_INCLUDE_DRAFTS=true`. Deprecated publishes with a banner and leaves recommendations. |
| `:page-solution-featured:` | no | `true` | Featured on the landing page. Omit otherwise. |
| `:page-solution-download:` | yes | `authenticated`, `public`, `none` | Who can fetch the release bundle |
| `:page-solution-platforms:` | no | subset of `self-managed`, `cloud` | Default both. Filters recommendations on Cloud vs Self-Managed pages. |
| `:page-solution-technologies:` | yes | comma list | Chips on the card; search facet |
| `:page-categories:` | yes | comma list from `valid-categories.yml` | Unknown values fail the build. List the specific subcategories the solution teaches (`Consumer Groups`, `Retention and Compaction`, `Pipelines`): only subcategory overlap creates recommendations between pages and solutions, and the top-level values are added automatically. Avoid catch-all values such as `Clients` or `Development`, which match dozens of pages and turn the card into noise. When one particular page is related, use `:page-solution-related-docs:` instead. |
| `:page-solution-use-cases:` | no | comma list | |
| `:personas:` | no | ids from `docs/modules/ROOT/partials/personas.yaml` | |
| `:page-solution-steps:` | yes | ordered comma list of step ids | The only source of step order. Each id is `pages/<id>.adoc` and `steps/<id>/commands.sh`; the Doc Detective spec is generated from the page. |
| `:page-solution-related-docs:` | recommended | fully qualified resource IDs | Must resolve. Warn when absent. These are the strongest "Build it in practice" edges on Product Docs, and the right tool for a single related page that a category would over-match. |
| `:page-solution-related-solutions:` | no | solution ids | |
| `:page-solution-superseded-by:` | when deprecated | solution id | |
| `:page-solution-step-duration:` | no (step pages) | integer minutes | |

Derived at build time, never authored: `page-solution-id`, `page-solution-repo`,
`page-solution-asset`, `page-solution-tag`, step navigation, and the
`page-solution` record the layouts render.

### Difficulty and assumed knowledge

`:page-solution-difficulty:` describes what the reader must *bring*, not how
deep the material goes. Depth is already carried by
`:page-solution-duration:` and the length of the step list, so a long
solution that asks nothing of the reader is still `beginner`.

Rate each of the three axes below, then take the highest row any single axis
reaches. One advanced axis makes the solution `advanced`.

| Axis | `beginner` | `intermediate` | `advanced` |
|---|---|---|---|
| Assumed knowledge | Docker, and nothing about Redpanda. | One or two Redpanda concepts the reader will have met in Product Docs, for example topics or consumer groups, plus comfort reading code in the solution's language. | Operational experience: security and ACLs, more than one cluster, Kubernetes, or schema compatibility rules. |
| What the reader must do | Every command is copy-paste. | The reader edits configuration or reads code. | The reader makes judgment calls that change the outcome. |
| External services | None to configure. | A free third-party account at most. | May need real infrastructure. |

Worked examples, as the kind of solution each label fits:

* A solution that streams events through a local compose stack and has the
  reader read Go but write none is `intermediate`: it assumes topics and
  consumer groups, and the reader reads code.
* A migration between two secured clusters, with ACLs and consumer-group
  offset translation, is `advanced` on every axis.
* A disaster-recovery walkthrough with failover and a Kubernetes variant is
  `advanced`: it assumes operational experience and the reader decides when
  to fail over.

`:page-solution-assumes:` names the same assumptions in the reader's words,
and the two together are what a reader uses to choose a solution: the label
sorts it against its siblings, the phrases say what to go and learn first.
Keep the phrases short and concrete (`topics`, `reading Go`), not sentences,
and keep them honest against the rubric above: `beginner` with
`schema compatibility rules` in the list is a contradiction, and
`tools/check-metadata.sh` warns about the likely cases.

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
  with one command (the step's last command block) and its captured expected
  output, then the one or two most likely failures and their fixes. The
  generated Doc Detective spec replays every command block of the step, this
  one last. A published step must have one or the other.
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
- The last step of every solution runs `scripts/verify.sh` and shows its output.
- Versions are pinned in `.env.example` before a solution is `published`. The
  nightly workflow overrides them with `latest` and opens an issue when a
  solution breaks.

### One source of truth for everything a page shows

No literal code in pages. Every listing block (`----` or `....`) carries
`[source,<lang>]` (or `[,<lang>]`) and contains only `include::` lines;
`tools/check-metadata.sh` fails on a typed command, a typed output, or a
pasted source file.

- Commands live in `solutions/<slug>/steps/<step-id>/commands.sh`, one tagged
  region per command block (`# tag::<name>[]` ... `# end::<name>[]`), and the
  page shows them with `include::example$steps/<step-id>/commands.sh[tag=<name>]`.
  The Verify command is the last command block of its step. Commands the
  overview shows (Clean up, extensions) live in `steps/overview/commands.sh`.
- Expected outputs are captured, never typed. `tools/capture-expected.sh <slug>`
  runs every command block on a fresh stack (`make clean && make up`) in step
  order and writes each command's stdout to
  `steps/<step-id>/expected/<name>.txt`; the page includes that file in a
  `[source,text]` block right after the command. Run it after changing
  behaviour, then review the diff before committing.
- Doc Detective specs are generated, never committed. `tools/gen-dd-specs.mjs`
  turns every step page into one spec: one `runShell` per command block, run
  exactly as shown (`bash`, `set -euo pipefail`, `.env` loaded, the solution
  directory as the working directory), plus a stdout check for every
  expected-output include (digits, timestamps, and hex ids are wildcarded;
  lines are matched in order; trailing whitespace is ignored). A command that
  cannot run in CI (a Cloud tab, a step covered elsewhere) carries the
  `[.manual]` role and is skipped with a note. `tools/run-doc-detective.sh`
  generates the specs into its run directory before it runs them;
  `check-metadata.sh` runs `gen-dd-specs.mjs --check` to make sure every step
  yields at least one runnable command and one output check and that every tag
  exists.
- `scripts/verify.sh` is unchanged by all of this: it is code, shown with a
  tagged include like any other file, and it stays the last step's command.
- A recording's engine is deliberately not declared, and a screenshot or
  recording only replaces the committed file when it meaningfully changed.
  Both are explained under "Recording engines and idempotence" below.
- Media is captured by the tests, never edited by hand. A step that shows the
  running system has `steps/<step-id>/media.json`: an array of Doc Detective
  browser steps (`goTo`, `find`, `wait`, `screenshot`, `record`, `stopRecord`;
  `{"runCommandTag": "<name>"}` expands to a command block so a recording can
  wrap it) that the generator appends after the step's command blocks, with
  output paths into `../../docs/modules/<slug>/images/`. Pages embed the
  results with `image::` or `video::`; `check-metadata.sh` fails on any image
  or video that is not such an output (`architecture.svg` excepted). Use
  `"overwrite": "aboveVariation"` with a small `maxVariation` so a run only
  rewrites a file when the picture really changed, which keeps the nightly
  media pull request quiet. The base context is headless Firefox at 1280x800;
  a spec that records is given headed Chrome, because that is the only engine
  that can record a browser in doc-detective 4.38.1. When you change a
  screenshot's `crop`, delete the old image first: `aboveVariation` compares
  against the existing file and refuses to compare images with different
  aspect ratios, so the first cropped capture must seed a new baseline.

### Recording engines and idempotence

Two settings on a `record` step look like details and are not.

**Leave `engine` undeclared.** doc-detective resolves it from the context, and
that resolution is what lets one `media.json` work on a laptop and on a
runner. `resolveRecordPlan` picks the `browser` engine only for a Chrome
context with `headless === false` and no app surface, and the `ffmpeg` engine
otherwise; `coerceRecordContextBrowser` says why in its own comment, "the
browser engine can't record headless". Declaring `browser` breaks any headless
context: the step does not fall back, it skips, with "Recording isn't
supported in headless mode with the browser engine. Use the ffmpeg engine to
record headless." Declaring `ffmpeg` breaks macOS, where capturing the screen
needs a screen-recording permission that no CI runner and no fresh laptop
grants. Undeclared, a headed Chrome context records its tab and a headless one
records the display, and both work.

That is also why the CI workflows install `xvfb` and run the suite under
`xvfb-run`: the generated spec pins headed Chrome for a recording, headed
Chrome needs a display, and a runner has none. It is why
`tools/run-doc-detective.sh` counts a SKIPPED test as a failure, too. A
recording step that skips is silent otherwise, and a run that recorded nothing
would report success.

`target` (`display`, `window`, `viewport`) is not set, because the schema says
it is "Ignored by the `browser` engine, which always captures its tab", and
the browser engine is the one both a laptop and a runner under `xvfb-run`
resolve to. It would only matter for a genuinely headless run.

**Use `overwrite: aboveVariation`, never `true`.** `true` re-encodes and
replaces the file on every run, so the committed recording differs after every
run, and the nightly would open a drift pull request every night for a file
nobody needs to look at. `aboveVariation` compares checkpoint screenshots
taken during the recording against a stored baseline and replaces the file
only when they differ meaningfully. It enables those checkpoints by itself;
point them somewhere git-ignored, outside `docs/modules/<slug>/images/`
(`.doc-detective/recording-checkpoints` in the flagship), because baseline
PNGs are neither published media nor allowed under the nightly's guard.

Screenshots already behave this way through `overwrite: aboveVariation` with a
`maxVariation`. Verify both when you change a media step: run the suite twice
from a clean stack, and the second run must leave
`docs/modules/<slug>/images/` untouched.

One rewrite is expected the first time CI records, and is not a bug. A capture
on a Linux runner is not byte-identical to one from a Mac (a Retina capture is
2x, so the same page records at twice the pixel dimensions), so the first
nightly to record a given file replaces it once and opens a drift pull request
saying so. After that the checkpoint baselines, which the nightly caches
between runs, keep it stable.

### What the nightly may change by itself

`nightly.yml` runs every solution's generated suite against the latest
Redpanda, Console, and Connect images and then acts on the result, so the
boundary of what an unattended run may rewrite is part of this contract.

It may change these, and only for the solution it just tested:

- `solutions/<slug>/steps/<step-id>/expected/<name>.txt`, the captured output
  of a documented command.
- `docs/modules/<slug>/images/<file>`, the captured screenshots and recordings.
- `solutions/<slug>/.env.example`, to pin an image version when a `latest`
  image is what broke the run.
- `docs/modules/<slug>/attachments/verification.json`, the manifest described
  below, which only the runner ever writes.

It may never change anything else: no page, no `commands.sh`, no `media.json`,
no `scripts/verify.sh`, no service source, no tooling, and nothing belonging to
another solution. `tools/nightly-allowed-change.sh` enforces that
mechanically, over both the suite's own output and anything the automated
investigation touches; a run that tries to go outside the list has its whole
change set discarded. A failing assertion must never be resolvable by editing
the assertion, so the one repair a nightly cannot make is the one that would
make a broken promise look kept.

Two outcomes reach you as a result:

- A pull request on `automation/nightly-<slug>`, when every spec passed and
  only captures changed. That is drift in what the system prints or renders,
  and the suite passing is the evidence that the documented outcome still
  holds. Review it like any capture change, and merge or close it promptly:
  while it is open the default branch's baseline is stale, so every later
  night lands back on it.
- An issue labelled `needs-human`, when a spec failed and nothing safe fixed
  it. That label means what it says: the documented outcome may no longer
  hold, and no automation can settle it. The issue names the failing specs,
  carries the investigation's diagnosis, and lists any file the investigation
  wanted to change but was not allowed to, which is usually the clearest
  pointer to what actually broke.

A fix pull request only ever appears after the whole suite has passed again
from a clean stack with the change in place, so a green nightly PR is a
statement that the solution still works, not just that the captures were
updated.

**A healthy nightly opens nothing at all.** Every documented command runs,
every captured output and every capture matches what is committed, the
verification manifest is rewritten with a new `run_at` and nothing else, and
the drift step skips a manifest-only change because there would be nothing for
a reviewer to look at. So silence is the expected result, and a pull request
means something genuinely moved: the output of a documented command, a
screenshot, or a recording whose checkpoints drifted. Treat one as a signal,
not as noise, which is the whole reason the manifest-only and byte-identical
cases are suppressed.

### verification.json is evidence, so nobody edits it

`tools/run-doc-detective.sh` writes
`docs/modules/<slug>/attachments/verification.json` at the end of every
passing run, from that run's own results file
(`tools/write-verification.mjs`). It records only what the run produced: how
many specs and steps ran, how many of those steps were commands from the pages
and how many were output checks, how many screenshots and recordings were
captured, the last line the verify script printed, the Redpanda version the
run used, and when the run started.

It exists because nothing at build time can see any of that. The Doc Detective
specs are generated into a transient run directory and never reach the Antora
catalog, so a page has no way to know what its own suite proved. The manifest
is an attachment, which the build does see.

Nobody edits this file, ever, and nothing authors it by hand: not a writer, not
a reviewer, not the model in the nightly's investigation, which is forbidden
it by prompt, denied it by the allowlist guard, and has manifest writing
switched off during its own reruns. Every number in it is a count from a run
that passed, or it is worthless. `tools/check-metadata.sh` treats a malformed
or incomplete manifest as an error for that reason (a valid one can only come
from the runner) and warns when a `published` solution has none.

To refresh it, run the suite: `tools/run-doc-detective.sh <slug>`. Commit the
result like any other capture. It is not checked for freshness, because the
nightly regenerates it on every passing run and opens a pull request when the
captures alongside it change.

## Production checklist

Before a solution goes `published`, every row of the Production considerations
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
- Inline code in prose is a tagged excerpt of at most about 40 lines that the
  surrounding paragraph actually explains. Add `tag::` regions to the source
  rather than duplicating code. Every full file the build-along reader needs
  goes in a collapsed block at the end of the step's "What happens inside"
  section, one per file, titled `.Complete source: <path>` with
  `[%collapsible]` and a `====` example block around the listing (language
  and file path on the listing). Commands readers type stay inline, and the
  `.Files for this step` attachments list stays.
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

Every step's spec is generated from its page by `tools/gen-dd-specs.mjs` (see
"One source of truth for everything a page shows"). The only hand-written
specs are `solutions/<slug>/tests/doc-detective/specs/_setup.json` (`make up`),
run once before the step specs (`beforeAny`), and `_teardown.json`
(`make clean`), once after (`afterAll`). They are not steps and are never
listed in `:page-solution-steps:`.

- `tools/run-doc-detective.sh <slug>` merges `tools/doc-detective.base.json`
  with the solution's `.doc-detective.json`, generates the step specs into
  its run directory, and runs them in step order. `make test-docs` calls it.
- Prefix resources a command creates with the solution slug so specs never
  collide. Never put credentials in `commands.sh` or in a page; the Cloud path
  reads them from `.env`.

## Review checklist

- [ ] `tools/check-metadata.sh` exits 0 with no warnings that matter.
- [ ] Title and intro state the business problem; outcomes are observable.
- [ ] Every paragraph passes the boundary rule; concepts are linked, not
      re-explained.
- [ ] Architecture diagram matches the compose file (same services, same
      topics).
- [ ] Every "In production" cell links a canonical page.
- [ ] Step 1 completes from the page and attachments alone (reviewer tries it).
- [ ] Every command and every expected output on a page is an include from
      `steps/<step-id>/`; outputs were captured with `tools/capture-expected.sh`
      and the generated spec replays them (`tools/run-doc-detective.sh`).
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

Prove the build from a scratch clone of your branch, and delete the clone in
the same command. A clone with its `node_modules` is about 2.3 GB, and a few
of them left behind fill the disk:

```bash
git clone -b <branch> . /tmp/solutions-proof && cd /tmp/solutions-proof \
  && npm ci && SOLUTIONS_INCLUDE_DRAFTS=true npm run build; \
  cd - && rm -rf /tmp/solutions-proof
```

`tools/run-doc-detective.sh` prunes its own reports to the newest two run
directories under `solutions/<slug>/.doc-detective/runs/` for the same reason.

## Labs content

`labs-docs/` and the legacy code directories (`docker-compose/`, `clients/`,
`data-transforms/`, `kubernetes/`, `connect-plugins/`, `setup-tests/`) are the
retired Redpanda Labs, frozen until each lab is promoted into a solution,
extracted into Product Docs, or retired with a redirect. Do not edit them.
