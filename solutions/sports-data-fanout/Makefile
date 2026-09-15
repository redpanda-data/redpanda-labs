# Sports data feed ingestion and fan-out
#
# The targets below are the contract every solution keeps so that CI, the
# Doc Detective specs, and readers all drive the stack the same way. This
# solution adds topics, schemas, evolve, replay, and test.
SHELL := /bin/bash
.DEFAULT_GOAL := help
COMPOSE ?= docker compose
SLUG := sports-data-fanout
RPK := $(COMPOSE) exec -T rpk rpk
GO_IMAGE ?= golang:1.26-alpine

# The three consumer groups. Everything that asks "has the fan-out caught up"
# asks about all three, because a fan-out that is only current for two of them
# has not caught up.
GROUPS := odds-engine market-state feed-archive
# Replication factor for `make topics`: 1 on the local broker, 3 on Redpanda
# Cloud. Read from .env so the Cloud path needs no Makefile edit.
REPLICAS := $(or $(shell sed -nE 's/^REDPANDA_TOPIC_REPLICAS=([0-9]+)$$/\1/p' .env 2>/dev/null),1)
SUBJECTS := sports.feed-value sports.odds-value sports.market-state-value

.PHONY: help up down topics schemas seed wait verify logs clean evolve replay test test-docs

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "  %-10s %s\n", $$1, $$2}'

.env:
	cp .env.example .env

up: .env ## Build the services, start every container, wait until all healthchecks pass
	$(COMPOSE) up -d --build --wait

down: .env ## Stop the services, keep data volumes
	$(COMPOSE) down

# tag::topics[]
topics: ## Create the four topics (idempotent)
	@# sports.feed is keyed by fixture, so six partitions is parallelism for the
	@# consumers without breaking per-fixture order.
	@$(RPK) topic create sports.feed -p 6 -r $(REPLICAS) -c retention.ms=604800000 || $(RPK) topic describe sports.feed >/dev/null
	@$(RPK) topic create sports.odds -p 6 -r $(REPLICAS) || $(RPK) topic describe sports.odds >/dev/null
	@# The desk's current view, keyed by fixture: compacted, so the latest state
	@# per fixture survives retention. segment.ms is what makes compaction
	@# visible within a minute on a local broker; Redpanda Cloud enforces a
	@# floor and rejects it, so fall back to the same topic without it.
	@# cleanup.policy=compact is not optional, it is the solution.
	@$(RPK) topic create sports.market-state -p 3 -r $(REPLICAS) -c cleanup.policy=compact -c segment.ms=60000 >/dev/null 2>&1 \
	  || $(RPK) topic create sports.market-state -p 3 -r $(REPLICAS) -c cleanup.policy=compact \
	  || $(RPK) topic describe sports.market-state >/dev/null
	@$(RPK) topic create sports.feed.dlq -p 1 -r $(REPLICAS) || $(RPK) topic describe sports.feed.dlq >/dev/null
	@$(RPK) topic list
# end::topics[]

# tag::schemas[]
schemas: ## Register the feed, odds and market-state schemas and set BACKWARD compatibility (idempotent)
	@$(RPK) registry schema create sports.feed-value --schema /schemas/feed_event.avsc --type avro >/dev/null
	@$(RPK) registry schema create sports.odds-value --schema /schemas/odds.avsc --type avro >/dev/null
	@$(RPK) registry schema create sports.market-state-value --schema /schemas/market_state.avsc --type avro >/dev/null
	@# BACKWARD is the level that lets a provider add a field without every
	@# consumer being redeployed first, and refuses the changes that would
	@# break one. Setting it after the first registration is deliberate: the
	@# first schema has nothing to be compatible with.
	@$(RPK) registry compatibility-level set $(SUBJECTS) --level BACKWARD >/dev/null
	@$(RPK) registry subject list
	@$(RPK) registry schema list $(SUBJECTS)
# end::schemas[]

# tag::evolve[]
evolve: ## Register v2 of the feed schema (adds provider) and restart the feed to write it
	@$(RPK) registry schema create sports.feed-value --schema /schemas/history/feed_event.v2.avsc --type avro
	@# The restarted feed reports on two matches the topic has not seen. A
	@# provider's (fixture, seq) pair is the identity of an event, so re-sending
	@# the same four matches would be a redelivery rather than new data, and the
	@# archive would correctly ignore every row of it.
	@FEED_SCHEMA_FILE=/schemas/history/feed_event.v2.avsc FIXTURES_FILE=/sample-data/fixtures-late.json \
	  $(COMPOSE) up -d --no-deps --wait feed
	@$(RPK) registry schema list sports.feed-value
# end::evolve[]

# tag::seed[]
seed: topics schemas ## Run the feed to its event cap and wait for all three consumers to catch up
	@echo "waiting for the feed to reach its event cap"
	@port=$${FEED_PORT:-$$(sed -nE 's/^FEED_PORT=//p' .env)}; port=$${port:-8090}; \
	for i in $$(seq 1 150); do \
	  done=$$(curl -fsS http://localhost:$$port/healthz 2>/dev/null | sed -nE 's/.*"done": *(true|false).*/\1/p'); \
	  if [ "$$done" = "true" ]; then curl -fsS http://localhost:$$port/healthz; break; fi; \
	  sleep 2; \
	done; \
	if [ "$$done" != "true" ]; then echo "the feed did not reach its cap in time (done: $$done)"; exit 1; fi
	@$(MAKE) --no-print-directory wait
# end::seed[]

# tag::wait[]
wait: ## Wait until all three consumer groups have caught up (lag 0, stable)
	@for i in $$(seq 1 $${WAIT_SECONDS:-180}); do \
	  described=$$($(RPK) group describe $(GROUPS) 2>/dev/null </dev/null | awk '$$1=="GROUP" {n++} END {print n+0}'); \
	  lag=$$($(RPK) group describe $(GROUPS) 2>/dev/null </dev/null | awk '$$1=="TOTAL-LAG" {s+=$$2} END {print s+0}'); \
	  unstable=$$($(RPK) group describe $(GROUPS) 2>/dev/null </dev/null | awk '$$1=="STATE" && $$2!="Stable" {b=1} END {print b+0}'); \
	  if [ "$$described" = 3 ] && [ "$$lag" = 0 ] && [ "$$unstable" = 0 ]; then \
	    echo "consumer groups $(GROUPS) all have lag 0 and are stable"; exit 0; fi; \
	  sleep 1; \
	done; \
	if [ "$$described" != 3 ]; then \
	  echo "gave up after $${WAIT_SECONDS:-180}s: only $$described of the three groups were describable (are odds-engine, market-state and connect all running, and does the user have describe on them?)"; \
	else \
	  echo "gave up after $${WAIT_SECONDS:-180}s: total lag across the three groups was $$lag, unstable=$$unstable. Against Redpanda Cloud set WAIT_SECONDS higher: the consumers are the same but the round trip is not."; \
	fi; exit 1
# end::wait[]

# tag::replay[]
replay: ## Replay the archive group from the start, without touching the other two
	@$(COMPOSE) stop connect >/dev/null
	@$(RPK) group seek feed-archive --to start
	@$(COMPOSE) start connect >/dev/null
	@$(MAKE) --no-print-directory wait
# end::replay[]

verify: ## Prove the outcome; prints PASS (n/n) or FAIL
	./scripts/verify.sh

logs: .env ## Follow the logs of every service
	$(COMPOSE) logs -f --tail=100

clean: .env ## Stop the services and delete their volumes
	$(COMPOSE) --profile '*' down -v --remove-orphans

test: ## Run the Go unit tests in a container
	docker run --rm -v "$(CURDIR)/services":/src -v "$(CURDIR)/schemas":/schemas:ro -v sports-data-fanout-gomod:/go/pkg/mod -w /src $(GO_IMAGE) sh -c 'go vet ./... && go test ./...'

test-docs: ## Run the Doc Detective specs for this solution (needs the repo checkout)
	@test -x ../../tools/run-doc-detective.sh || { echo "make test-docs needs the solutions repo checkout (tools/run-doc-detective.sh)"; exit 1; }
	../../tools/run-doc-detective.sh $(SLUG)
