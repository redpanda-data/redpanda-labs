# Doc Detective specs for __title__

How the harness works is documented once, in `tools/README.md` at the
repository root: the step specs are generated from the step pages, so the only
files committed here are `_setup.json` and `_teardown.json`. Read that first,
and do not repeat it here.

This file is for what is true of **this solution only**. Delete any heading
below that does not apply, and delete this paragraph.

```
tools/run-doc-detective.sh __slug__    generate and run the specs
tools/capture-expected.sh __slug__     record expected output from a live stack
make test-docs                         the same runner, from this directory
```

## Order

Say whether the steps have to run in `:page-solution-steps:` order from a
clean stack, and why. If one step's output depends on state an earlier step
created, write down the causal link, because the reason is never obvious from
the specs and it is what a future reader needs when a spec fails out of order.

## What a run needs

List anything beyond Docker and this repository: a licence key in `.env`, a
cloud credential, a port that must be free, an image that must be pulled. Say
what the failure looks like when it is missing, so the next person recognises
it instead of debugging it.

## Slow steps

Name the steps that take noticeably longer than the rest and why, so a slow
run is not mistaken for a hang.

## Media

Name each screenshot and recording this solution captures, which step owns it
(`steps/<step-id>/media.json`), and what it is meant to show. If the solution
captures none, say so and say why, so nobody assumes it was an oversight.
