# Multiplayer Gaming
#
# The targets below are the contract every solution keeps so that CI, the
# Doc Detective specs, and readers all drive the stack the same way.
SHELL := /bin/bash
.DEFAULT_GOAL := help
COMPOSE ?= docker compose
SLUG := multiplayer-gaming
TOPIC := $(SLUG).events

.PHONY: help up down seed verify logs clean test-docs

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "  %-10s %s\n", $$1, $$2}'

.env:
	cp .env.example .env

up: .env ## Start every service and wait until all healthchecks pass
	$(COMPOSE) up -d --wait

down: ## Stop the services, keep data volumes
	$(COMPOSE) down

seed: ## Create topics and load sample data
	$(COMPOSE) exec -T rpk rpk topic create $(TOPIC) -p 3 -r 1 || $(COMPOSE) exec -T rpk rpk topic describe $(TOPIC) >/dev/null
	$(COMPOSE) exec -T rpk sh -c 'rpk topic produce $(TOPIC) -f "%v\n" < /sample-data/events.ndjson'

verify: ## Prove the outcome; prints PASS (n/n) or FAIL
	./scripts/verify.sh

logs: ## Follow the logs of every service
	$(COMPOSE) logs -f --tail=100

clean: ## Stop the services and delete their volumes
	$(COMPOSE) down -v --remove-orphans

test-docs: ## Run the Doc Detective specs for this solution (needs the repo checkout)
	@test -x ../../tools/run-doc-detective.sh || { echo "make test-docs needs the solutions repo checkout (tools/run-doc-detective.sh)"; exit 1; }
	../../tools/run-doc-detective.sh $(SLUG)
