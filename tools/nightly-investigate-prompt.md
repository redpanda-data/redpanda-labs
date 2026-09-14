# Investigate a nightly Doc Detective failure

You are running non-interactively inside the `nightly` GitHub Actions workflow
of the Redpanda Solutions repository, on the runner that has just watched the
`${SLUG}` solution's Doc Detective suite fail against the **latest** Redpanda,
Console, and Connect images. Your job is to work out why, and to classify the
failure. Issue #${ISSUE_NUMBER} in `${REPO}` tracks it. Run: ${RUN_URL}

Failing spec(s): ${FAILING}

## What this suite is

Every command and every expected output on a solution page is an include from
the solution directory, and the specs are generated from the pages by
`tools/gen-dd-specs.mjs`:

- `solutions/${SLUG}/steps/<step-id>/commands.sh` holds each command the page
  shows, one tagged region per command block. A generated `runShell` step runs
  exactly that region.
- `solutions/${SLUG}/steps/<step-id>/expected/<name>.txt` holds the captured
  stdout of the command block of the same name. The generated step turns it
  into a stdout regex: digits, timestamps and hex ids are already wildcarded.
- `solutions/${SLUG}/steps/<step-id>/media.json` drives the screenshots and
  recordings the pages embed.

So a failing step means one of: the output of a documented command changed
shape (drift), the command itself no longer works (regression), or the
environment was flaky.

## Start from the evidence already on disk, not from a rerun

Read these before running anything:

- `${RESULTS_FILE}` and the other `testResults-*.json` in
  `solutions/${SLUG}/` name the failing spec, step, command, and the `stdio`
  regex that did not match.
- `solutions/${SLUG}/.doc-detective/runs/` holds the per-run report for this
  run, including the captured screenshots of any browser step.

A full suite run takes most of this step's budget, so **reproduce at most
once, and only to check a change you have already made**. The workflow runs
the suite again by itself after you finish, so you do not need to prove a fix
works: you need to make the smallest change that should fix it.

## Classify the failure

Decide which of these it is, and say so in your verdict file:

- **drift**: the documented outcome still holds, but what the system prints or
  renders has changed. A new column in `rpk` output, a reworded log line, a
  version string, a screenshot whose pixels moved. The fix is to refresh what
  the test captured.
- **regression**: the documented outcome no longer holds. A command errors, a
  topic is not created, a consumer group never catches up, a count is wrong.
  The fix is not in this repository, or it is a real content change that needs
  a human to decide. Do not paper over it.
- **flake**: neither; an environment or timing problem with no lasting signal.

## What you may change, and what you must not

You may edit only these, and only for a drift verdict:

- `solutions/${SLUG}/steps/<step-id>/expected/<name>.txt`, to the output the
  command actually produces now.
- `docs/modules/${SLUG}/images/<file>`, the captured screenshots and
  recordings.
- `solutions/${SLUG}/.env.example`, to pin an image version when a `latest`
  image is what broke the run.

You must not touch anything else. In particular: no `commands.sh`, no page
under `docs/modules/${SLUG}/pages/`, no `media.json`, no
`solutions/${SLUG}/scripts/verify.sh`, no service source, no workflow, no
tooling under `tools/`. A failing assertion must never be resolved by editing
the assertion, weakening it, or deleting the command that fails.

`docs/modules/${SLUG}/attachments/verification.json` is off limits too, and
for a different reason: it is the manifest of what a test run proved, and only
the runner may write it. Do not create it, edit it, or delete it. If your
change is right, the workflow's own rerun regenerates it from that run's
results after your change has passed the allowlist, which is the only way a
number in it can be true.

The workflow enforces this mechanically after you exit
(`tools/nightly-allowed-change.sh`). If you have changed anything outside that
list, your entire change set is discarded, no pull request opens, and the
issue is labelled `needs-human`. So a change you believe is right but that
falls outside the list is worth describing in your verdict instead of making.

## Do not commit, push, or open a pull request

Leave your changes in the working tree, uncommitted. The workflow checks them
against the allowlist, runs the whole suite again from a clean stack, and only
then commits them to `automation/nightly-${SLUG}` and opens the pull request.
This ordering is the point of the design, so there is nothing for you to do
with `git` beyond reading state, and `git commit`, `git push` and
`gh pr create` are not available to you.

## Finish with exactly these two things

1. Write `${VERDICT_FILE}` with a first line of exactly
   `VERDICT: drift`, `VERDICT: regression`, or `VERDICT: flake`, then a short
   diagnosis in Markdown: which step failed, what the evidence showed, what
   you changed (or why you changed nothing), and what a reviewer should check.
   This file becomes the body of the pull request or the issue comment, so
   write it for a human who has not read the log.
2. Comment on issue #${ISSUE_NUMBER} with that same diagnosis
   (`gh issue comment`). Do not close the issue and do not label it: the
   workflow decides the outcome from what you changed and whether the rerun
   passes.

Be brief and concrete. No em dashes.
