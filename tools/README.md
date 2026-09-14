# The solutions test harness

This directory holds the shared harness every solution is tested with. It is
the source of truth for how testing works in this repository. Each solution's
`tests/doc-detective/README.md` covers only what is specific to that solution.

Read this before changing a step page, and before adding a rule to the output
generalizer.

## The model: the test is derived from the page

Other Redpanda docs repositories commit a Doc Detective spec next to the page
it verifies. This repository does not. **Step specs are generated at run time
from the page's own includes**, so a test cannot check something different
from what the page shows. The only spec files on disk are `_setup.json` and
`_teardown.json`.

That is the whole point of the design. A page and its test cannot drift,
because there is only one artifact.

```
tools/run-doc-detective.sh <slug>     generate the specs, then run them
tools/capture-expected.sh <slug>      record expected output from a live stack
tools/gen-dd-specs.mjs                the generator itself
tools/check-metadata.sh [<slug>]      the metadata contract
tools/changed-solutions.sh [base]     which slugs CI should test
tools/doc-detective.base.json         config every solution inherits
```

## How the generator decides what to run

It never looks at the code in a block. Classification is **the path of the
include inside the block**, nothing else.

Inside a delimited block (`----` or `....`), the generator matches only
`include::example$<path>[<attrs>]` lines, and only two paths mean anything:

| Include | Becomes |
|---|---|
| `example$steps/<step-id>/commands.sh` with `tags=<tag>` | a `runShell` step |
| `example$steps/<step-id>/expected/<tag>.txt` | the stdout check for the command above it |
| any other `steps/...` path | a hard error |
| any other `example$` path | ignored, rendered only |

The `<step-id>` is taken from the page's own id, so a step page can only run
its own commands. Including another step's `commands.sh` is rejected.

The command text is the region between `# tag::<tag>[]` and `# end::<tag>[]`
in `steps/<step-id>/commands.sh`. Each `runShell` runs with
`set -euo pipefail`, `.env` loaded, the working directory set to the solution
directory, and a 600 second timeout, which is the same way
`capture-expected.sh` ran the command when it recorded the output being
compared against.

### The rules it enforces rather than guesses

The generator fails the run instead of emitting a spec that tests something
the page does not show:

- `tags=` is required on a `commands.sh` include.
- An expected-output block must **directly follow** its command block.
- The `.txt` filename must equal the command's tag.
- The tagged region must exist in `commands.sh` and must not be empty.
- A missing `expected/<tag>.txt` aborts generation, naming the page and line.

`[.manual]` (or `role=manual`) marks a command as shown but never run, and
pairing expected output with a manual command is itself an error.

## Expected output is captured, never typed

`tools/capture-expected.sh <slug>` walks the steps in `:page-solution-steps:`
order, runs every runnable command block exactly as the generator would, and
writes each command's stdout to
`solutions/<slug>/steps/<step-id>/expected/<tag>.txt`.

Run it on a fresh stack (`make clean && make up`), which is the state the Doc
Detective run also starts from. After a behaviour change, run it and review
the diff. **Do not run it and then immediately run the specs against the same
stack**: the capture leaves the stack in its end state, and the specs expect
to start clean.

## The output generalizer, and why it needs maintenance

A captured file is turned into a regex, because real output contains values
that change every run. `expectedRegex` in `gen-dd-specs.mjs` generalizes
digits, timestamps, UUIDs, long hex ids, Postgres LSNs, and bracketed sets,
and escapes everything else literally.

**Every new shape of volatile output needs a rule here.** That is the standing
maintenance cost of this design. It fails closed, so an unmatched pattern is a
red test and never a silent pass, which makes the cost visible rather than
dangerous.

Three rules exist because they had already broken a suite:

| Output | Why the naive pattern failed |
|---|---|
| `2026-09-14 14:08:31` | a timestamp became `\S+`, which cannot match a value containing a space |
| `00000000/0196C4B9` | a Postgres LSN is hex, so generalizing only digit runs left `A-F` literal |
| `[datalake_iceberg cloud_storage ...]` | `rpk` prints sets in map order, which differs between runs |

When a spec fails with `Returned exit code 0. Couldn't find expected output`,
the command succeeded and the pattern is wrong. Suspect the generalizer before
the page. Read the actual output from
`solutions/<slug>/.doc-detective/runs/<timestamp>/testResults.json` rather
than re-running the stack to watch it again.

Adding a rule: place it before the digit rule if it contains digits, give it
its own placeholder rather than reusing `S` if the value can contain a space,
and prove it both ways. A looser pattern must still reject output that is
genuinely wrong, so check a negative control, not just that the real output
now matches.

## How CI picks up a solution

There is no list of solutions anywhere. `tools/changed-solutions.sh` finds
them:

```
find solutions -mindepth 1 -maxdepth 1 -type d
```

`ci.yml` tests the slugs a pull request touches, `nightly.yml` passes `--all`,
and both fan out into `test-solution.yml` as a reusable workflow, once per
slug. Creating the directory is all it takes for a new solution to be tested.
`tools/new-solution.sh <slug>` scaffolds it.

What a new solution still costs by hand: its `_setup.json` and
`_teardown.json`, which are solution-specific, and capturing its expected
output against a real environment, including any licence or secret that
environment needs.

## Known gap

**A command pasted literally into a step page is silently untested.** It
renders identically to a tested one, and the generator cannot see it, because
recognition is by include path. Only the rule in `CONTRIBUTING.md` ("Never
paste source into a page") prevents it.

Closing this means a check in `check-metadata.sh` that flags any source block
in a step page whose body is not an `include::example$`. Until that exists,
"every command on the page is tested" is a convention, not a guarantee.
