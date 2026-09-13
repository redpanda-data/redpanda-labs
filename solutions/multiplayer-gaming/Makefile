# Multiplayer Gaming
#
# The targets below are the contract every solution keeps so that CI, the
# Doc Detective specs, and readers all drive the stack the same way. This
# solution adds topics, schemas, proto, and test.
SHELL := /bin/bash
.DEFAULT_GOAL := help
COMPOSE ?= docker compose
SLUG := multiplayer-gaming
RPK := $(COMPOSE) exec -T rpk rpk
BUF_VERSION ?= 1.57.2
GO_IMAGE ?= golang:1.26-alpine

TOPICS := game.player-events game.match-events game.achievements game.player-events.dlq
SUBJECTS := game.player-events-value game.match-events-value game.achievements-value

.PHONY: help up down topics schemas seed verify logs clean proto test test-docs

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
	@$(RPK) topic create game.player-events -p 6 -r 1 -c retention.ms=604800000 || $(RPK) topic describe game.player-events >/dev/null
	@$(RPK) topic create game.match-events -p 3 -r 1 || $(RPK) topic describe game.match-events >/dev/null
	@$(RPK) topic create game.achievements -p 3 -r 1 || $(RPK) topic describe game.achievements >/dev/null
	@$(RPK) topic create game.player-events.dlq -p 1 -r 1 || $(RPK) topic describe game.player-events.dlq >/dev/null
	@$(RPK) topic list
# end::topics[]

# tag::schemas[]
schemas: ## Register the GameEvent schema (v1, then BACKWARD, then v2) for every topic (idempotent)
	@for s in $(SUBJECTS); do \
	  $(RPK) registry schema create $$s --schema /proto/history/game_events.v1.proto --type protobuf >/dev/null; \
	done
	@$(RPK) registry compatibility-level set $(SUBJECTS) --level BACKWARD >/dev/null
	@for s in $(SUBJECTS); do \
	  $(RPK) registry schema create $$s --schema /proto/game_events.proto --type protobuf >/dev/null; \
	done
	@$(RPK) registry subject list
	@$(RPK) registry schema list $(SUBJECTS)
# end::schemas[]

# tag::seed[]
seed: topics schemas ## Let the simulator produce SIM_EVENTS_MAX events and wait until it stops
	@echo "waiting for the simulator to reach its event cap"
	@port=$${SIMULATOR_PORT:-$$(sed -nE 's/^SIMULATOR_PORT=//p' .env)}; port=$${port:-8090}; \
	for i in $$(seq 1 150); do \
	  state=$$(curl -fsS http://localhost:$$port/stats 2>/dev/null | sed -nE 's/.*"state": *"([^"]+)".*/\1/p'); \
	  if [ "$$state" = "capped" ]; then curl -fsS http://localhost:$$port/stats; exit 0; fi; \
	  sleep 2; \
	done; echo "simulator did not reach its cap in time (state: $$state)"; exit 1
# end::seed[]

verify: ## Prove the outcome; prints PASS (n/n) or FAIL
	./scripts/verify.sh

logs: .env ## Follow the logs of every service
	$(COMPOSE) logs -f --tail=100

clean: .env ## Stop the services and delete their volumes
	$(COMPOSE) down -v --remove-orphans

proto: ## Regenerate services/internal/gamepb from proto/game_events.proto (buf in a container)
	docker run --rm -v "$(CURDIR)":/work -w /work bufbuild/buf:$(BUF_VERSION) generate

test: ## Run the Go unit tests in a container
	docker run --rm -v "$(CURDIR)/services":/src -v multiplayer-gaming-gomod:/go/pkg/mod -w /src $(GO_IMAGE) sh -c 'go vet ./... && go test ./...'

test-docs: ## Run the Doc Detective specs for this solution (needs the repo checkout)
	@test -x ../../tools/run-doc-detective.sh || { echo "make test-docs needs the solutions repo checkout (tools/run-doc-detective.sh)"; exit 1; }
	../../tools/run-doc-detective.sh $(SLUG)
