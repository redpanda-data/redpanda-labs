# Sample data

Deterministic input for `make seed`. Keep it small (a few KB) and commit it: CI
and `scripts/verify.sh` count on exact numbers, so a check like "the topic
holds 3 events" stays true on every run.

| File | Loaded by | Shape |
|---|---|---|
| `events.ndjson` | `make seed` (`rpk topic produce`) | one JSON object per line |

Generated data belongs in a service (a simulator with a fixed seed), not here.
Document the generator's seed and event cap so `verify.sh` can assert on them.
