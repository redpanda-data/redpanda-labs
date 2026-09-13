# Sample data

| File | Loaded by | Shape |
|---|---|---|
| `players.json` | the simulator (`PLAYERS_FILE`, mounted at `/sample-data`) | roster: `id` and `display_name` |

The events themselves are not committed. The simulator generates them from
`SIM_SEED` with its own simulated clock, so the same seed produces the same
events on every run, and it stops at `SIM_EVENTS_MAX` so `scripts/verify.sh`
can assert exact counts. `SIM_PLAYERS` picks the first N roster entries; if N
is larger than the roster, synthetic players fill the gap.
