# Sports data feed ingestion and fan-out

Code for the sports data fan-out solution: one provider feed ingested once and
read by three independent consumers, an odds engine, a trading desk view, and
a settlement archive. The guided walkthrough lives on the docs site at
`/solutions/sports-data-fanout/`; this directory is what `make` drives and what
the download bundle contains.

## Run it

```bash
make up       # build the three Go services, start the stack, wait for every healthcheck
make topics   # sports.feed (6p), sports.odds (6p), sports.market-state (3p, compacted), sports.feed.dlq (1p)
make schemas  # register the feed, odds and market-state Avro schemas, then set BACKWARD compatibility
make seed     # topics + schemas, then run the feed to its cap and wait for all three groups
make wait     # block until odds-engine, market-state and feed-archive all have lag 0
make verify   # prints PASS (8/8) when the system does what the docs claim
make evolve   # register v2 of the feed schema and restart the feed against it
make replay   # send the archive group back to the start, without touching the other two
make test     # go vet and the unit tests, in a container
make clean    # stop and delete volumes
```

`make help` lists every target. Versions, feed settings and host ports are
pinned in `.env` (copied from `.env.example` on the first `make up`). Change
the `*_PORT` variables there when another stack already uses the defaults.

### Run against Redpanda Cloud

The same stack runs against a Redpanda Cloud Serverless cluster. In `.env`,
set `COMPOSE_PROFILES=` (empty, so the local `redpanda` and `console`
containers are skipped), `REDPANDA_BROKERS` to the bootstrap server URL,
`REDPANDA_TLS_ENABLED=true`, `REDPANDA_SASL_MECHANISM=SCRAM-SHA-256`, the
SCRAM user and password, `REDPANDA_SCHEMA_REGISTRY_URL` to the cluster's
registry URL, and `REDPANDA_TOPIC_REPLICAS=3`. Raise `LATENCY_BUDGET_MS`: the
consumers are the same, but the round trip is not.

The grants that user needs are declared in `cloud-acls.conf`, which is what
the nightly cloud run uses, so the documented ACLs and the tested ones cannot
drift apart silently.

## Layout

```
schemas/          the Avro contract: feed_event, odds, market_state
schemas/history/  the v2 change the registry accepts, and the one it refuses
services/feed/    the provider feed (Go): seeded, bursty, keyed by fixture
services/odds/    the odds engine (Go): group odds-engine -> sports.odds
services/risk/    the market-state service (Go): group market-state -> compacted topic
services/internal/ the shared contract: wire format, schema lookups, decoding
connect/          the settlement archive: one Redpanda Connect pipeline, no code
postgres/         the archive table, keyed on the provider's (fixture, seq)
sample-data/      the fixtures the feed reports on
scripts/verify.sh eight checks, all read from the log; prints PASS (8/8)
steps/<step-id>/  the commands each docs page shows, and their expected output
tests/            the Doc Detective setup and teardown specs
```

## Change the code

`make test` runs `go vet` and the unit tests in a container, so Go is not
required on the host. The tests worth knowing about:

- `services/feed/sim` asserts the feed is deterministic, that its sequence
  numbers are contiguous per fixture, and that every probability it emits can
  be priced. That last one is a contract between the two halves of this
  solution: without it the generator can drift into values the odds engine
  rejects, and the only symptom is a counter nobody looks at.
- `services/odds/pricing` covers the three reasons a price is not published.
- `services/risk/state` covers the fold, including that replaying the same
  events leaves the same state.
- `services/internal/feed` encodes and decodes against the real schema files,
  including both versions at once.

After changing anything a docs page shows, run
`tools/capture-expected.sh sports-data-fanout` from the repository root on a
fresh stack, and review the diff. Expected output is captured, never typed.

## Docs

The pages are in `docs/modules/sports-data-fanout/pages/`. Every command they
show is a tagged region in `steps/<step-id>/commands.sh`, every code excerpt
is an `include::example$` of a file in this directory, and the Doc Detective
specs are generated from the pages at run time.
