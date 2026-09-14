# Schema Registry Migration
#
# The targets below are the contract every solution keeps so that CI, the
# Doc Detective specs, and readers all drive the stack the same way. This
# solution adds the migration itself: register schemas on the Confluent
# source, create the shadow link, produce and consume records, pause schema
# replication and fail the topics over, and produce on Redpanda.
SHELL := /bin/bash
.DEFAULT_GOAL := help
COMPOSE ?= docker compose
SLUG := schema-registry-migration
RPK := $(COMPOSE) exec -T rpk rpk
CLIENT := $(COMPOSE) exec -T client
# The link name, from .env when it exists.
LINK := $(or $(shell sed -nE 's/^SHADOW_LINK=(.+)$$/\1/p' .env 2>/dev/null),schema-registry-migration)

.PHONY: help up down seed migrate verify logs clean test-docs \
        register-schemas register-complex-schemas link describe status compare \
        produce consume consume-shadow-registry consume-redpanda wait-topics \
        pause resume failover wait-failover produce-redpanda

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "  %-26s %s\n", $$1, $$2}'

.env:
	cp .env.example .env

up: .env ## Build the client image, start every container, wait until all healthchecks pass
	$(COMPOSE) up -d --build --wait

down: .env ## Stop the services, keep data volumes
	$(COMPOSE) down

# tag::source[]
register-schemas: ## Register orders-value (v1, BACKWARD, v2) and customers-value on the Confluent source
	@$(CLIENT) /scripts/register-schemas.sh

register-complex-schemas: ## Register a schema reference, a FULL_TRANSITIVE override, a JSON Schema, and a Protobuf subject on the source
	@$(CLIENT) /scripts/register-complex-schemas.sh

produce: ## Produce the seed records (3 orders, 2 customers, 1 shipment) to the Confluent broker
	@$(CLIENT) python3 /scripts/produce_topic_data.py seed

seed: register-schemas register-complex-schemas produce ## Everything the source holds before the migration starts (idempotent)
# end::source[]

# tag::link[]
link: ## Create the shadow link from config/shadow-link.yaml
	@$(RPK) shadow create --config-file /config/shadow-link.yaml --no-confirm

describe: ## Show the link's Schema Registry replication settings
	@$(RPK) shadow describe $(LINK) --print-registry

status: ## Show the link's replication status: tasks, topics, and the Schema Registry inventory
	@$(RPK) shadow status $(LINK)

compare: ## Wait until both registries agree, then print subjects, versions, IDs, types, compatibility, and references side by side
	@$(CLIENT) python3 /scripts/compare_registries.py
# end::link[]

# tag::consume[]
consume: ## Read and decode the records from the Confluent broker with the Confluent registry
	@$(CLIENT) python3 /scripts/consume_topic_data.py

consume-shadow-registry: ## Read from the Confluent broker, but resolve the schema IDs against the Redpanda registry
	@$(CLIENT) env SR_URL=http://redpanda:8081 python3 /scripts/consume_topic_data.py

consume-redpanda: ## Read and decode the records from Redpanda only: its broker and its registry
	@$(CLIENT) env SR_URL=http://redpanda:8081 BOOTSTRAP_SERVERS=redpanda:9092 python3 /scripts/consume_topic_data.py

wait-topics: ## Wait until the three shadow topics hold every source record, then show their state
	@for i in $$(seq 1 60); do \
	  hwm=$$($(RPK) shadow status $(LINK) --print-topic 2>/dev/null </dev/null | awk '/^ +[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+$$/ {s+=$$4} END {print s+0}'); \
	  if [ "$$hwm" -ge 6 ]; then echo "shadow topics orders, customers, shipping hold $$hwm records"; $(RPK) shadow status $(LINK) --print-topic; exit 0; fi; \
	  sleep 2; \
	done; echo "shadow topics did not catch up in time (destination high watermarks sum to $$hwm)"; exit 1
# end::consume[]

# tag::cutover[]
pause: ## Pause Schema Registry replication: the replicated contexts on Redpanda become writable
	@$(COMPOSE) exec -T -e SHADOW_LINK=$(LINK) rpk /scripts/set-paused.sh true

resume: ## Resume Schema Registry replication (only meaningful before failover)
	@$(COMPOSE) exec -T -e SHADOW_LINK=$(LINK) rpk /scripts/set-paused.sh false

failover: ## Fail every shadow topic over: they stop replicating and become writable (irreversible)
	@$(RPK) shadow failover $(LINK) --all --no-confirm
	@$(MAKE) --no-print-directory wait-failover

wait-failover: ## Wait until every shadow topic reports FAILED_OVER
	@for i in $$(seq 1 60); do \
	  n=$$($(RPK) shadow status $(LINK) --print-topic 2>/dev/null </dev/null | grep -cE '^Name: (orders|customers|shipping), State: FAILED_OVER'); \
	  if [ "$$n" -eq 3 ]; then $(RPK) shadow status $(LINK) --print-topic; exit 0; fi; \
	  sleep 2; \
	done; echo "topics did not reach FAILED_OVER in time"; $(RPK) shadow status $(LINK) --print-topic; exit 1

produce-redpanda: ## Produce one new order to Redpanda, resolving the schema from the Redpanda registry
	@$(CLIENT) env SR_URL=http://redpanda:8081 BOOTSTRAP_SERVERS=redpanda:9092 python3 /scripts/produce_topic_data.py cutover

migrate: link compare wait-topics pause failover produce-redpanda ## The whole migration after `make seed`: link, wait, cut over, produce on Redpanda
# end::cutover[]

verify: ## Prove the outcome; prints PASS (n/n) or FAIL
	./scripts/verify.sh

logs: .env ## Follow the logs of every service
	$(COMPOSE) logs -f --tail=100

clean: .env ## Stop the services and delete their volumes
	$(COMPOSE) down -v --remove-orphans

test-docs: ## Run the Doc Detective specs for this solution (needs the repo checkout)
	@test -x ../../tools/run-doc-detective.sh || { echo "make test-docs needs the solutions repo checkout (tools/run-doc-detective.sh)"; exit 1; }
	../../tools/run-doc-detective.sh $(SLUG)
