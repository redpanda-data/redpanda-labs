# Kafka Migration
#
# The targets below are the contract every solution keeps so that CI, the
# Doc Detective specs, and readers all drive the stack the same way. This
# solution adds the migration path: topics, schemas, workload,
# migrator-access, migrate, schema-v2, lag, and the cutover targets.
SHELL := /bin/bash
.DEFAULT_GOAL := help
COMPOSE ?= docker compose
SLUG := kafka-migration
RPK_SOURCE := $(COMPOSE) exec -T rpk-source rpk
RPK_TARGET := $(COMPOSE) exec -T rpk-target rpk

# .env is the one place for versions, ports, and credentials. make reads it
# too (and creates it from .env.example when missing) so recipes can use the
# same names as the compose file.
-include .env
export

.PHONY: help up down topics schemas workload migrator-access migrate schema-v2 lag wait-lag \
        stop-consumer wait-offsets consumer-target stop-producer sr-readwrite cutover \
        seed verify logs clean test-docs

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "  %-16s %s\n", $$1, $$2}'

.env:
	cp .env.example .env

up: .env ## Start both clusters, both Consoles, and the rpk helpers; wait until every healthcheck passes
	$(COMPOSE) up -d --wait

down: .env ## Stop every service, keep data volumes
	$(COMPOSE) --profile '*' down

# tag::topics[]
topics: ## Create the four shop.* topics on the source with their real configurations (idempotent)
	@$(RPK_SOURCE) topic create shop.orders -p 12 -r 1 -c retention.ms=604800000 -c compression.type=snappy \
	  || $(RPK_SOURCE) topic describe shop.orders >/dev/null
	@$(RPK_SOURCE) topic create shop.customer-profiles -p 6 -r 1 -c cleanup.policy=compact \
	  || $(RPK_SOURCE) topic describe shop.customer-profiles >/dev/null
	@$(RPK_SOURCE) topic create shop.inventory-events -p 8 -r 1 -c cleanup.policy=compact,delete -c retention.ms=86400000 \
	  || $(RPK_SOURCE) topic describe shop.inventory-events >/dev/null
	@$(RPK_SOURCE) topic create shop.alerts -p 3 -r 1 -c retention.ms=3600000 \
	  || $(RPK_SOURCE) topic describe shop.alerts >/dev/null
	@$(RPK_SOURCE) topic list
# end::topics[]

# tag::schemas[]
schemas: ## Register the Avro schema of every topic in the source Schema Registry (idempotent)
	@$(RPK_SOURCE) registry schema create shop.orders-value --schema /schemas/order.avsc --type avro >/dev/null
	@$(RPK_SOURCE) registry schema create shop.customer-profiles-value --schema /schemas/customer-profile.avsc --type avro >/dev/null
	@$(RPK_SOURCE) registry schema create shop.inventory-events-value --schema /schemas/inventory-event.avsc --type avro >/dev/null
	@$(RPK_SOURCE) registry schema create shop.alerts-value --schema /schemas/alert.avsc --type avro >/dev/null
	@$(RPK_SOURCE) registry schema list shop.orders-value shop.customer-profiles-value shop.inventory-events-value shop.alerts-value
# end::schemas[]

# tag::workload[]
workload: .env ## Start the legacy application (producer and the orders-service consumer) against the source
	$(COMPOSE) up -d producer orders-consumer
	@echo "waiting for orders-service to commit offsets on every partition"
	@for i in $$(seq 1 60); do \
	  n=$$($(RPK_SOURCE) group describe orders-service --print-commits 2>/dev/null </dev/null | awk '$$1 == "shop.orders" && $$3 ~ /^[0-9]+$$/' | wc -l | tr -d ' '); \
	  if [ "$$n" = 12 ]; then echo "orders-service has committed offsets on 12 partitions"; exit 0; fi; \
	  sleep 2; \
	done; echo "orders-service did not commit offsets in time"; exit 1
# end::workload[]

# tag::migrator-access[]
migrator-access: ## Create the migrator user on both clusters, grant least-privilege ACLs, and put the target Schema Registry in IMPORT mode (idempotent)
	@$(RPK_SOURCE) security user create $(MIGRATOR_USER) -p '$(MIGRATOR_PASSWORD)' --mechanism SCRAM-SHA-256 2>/dev/null \
	  || echo "$(MIGRATOR_USER) already exists on the source"
	@$(RPK_TARGET) security user create $(MIGRATOR_USER) -p '$(MIGRATOR_PASSWORD)' --mechanism SCRAM-SHA-256 2>/dev/null \
	  || echo "$(MIGRATOR_USER) already exists on the target"
	@$(COMPOSE) exec -T rpk-source /scripts/migrator-acls.sh source
	@$(COMPOSE) exec -T rpk-target /scripts/migrator-acls.sh target
	@$(RPK_TARGET) registry mode set --mode IMPORT
# end::migrator-access[]

# tag::migrate[]
migrate: .env ## Start Redpanda Migrator and wait until it is ready
	$(COMPOSE) up -d --wait migrator
	@echo "waiting for the four shop.* topics to appear on the target"
	@for i in $$(seq 1 60); do \
	  n=$$($(RPK_TARGET) topic list 2>/dev/null </dev/null | awk '$$1 ~ /^shop\./' | wc -l | tr -d ' '); \
	  if [ "$$n" = 4 ]; then $(RPK_TARGET) topic list; exit 0; fi; \
	  sleep 2; \
	done; echo "the migrator did not create the topics in time"; exit 1
# end::migrate[]

# tag::schema-v2[]
schema-v2: ## Register version 2 of the order schema on the source while the migrator runs (idempotent)
	@$(RPK_SOURCE) registry schema create shop.orders-value --schema /schemas/order-v2.avsc --type avro
# end::schema-v2[]

lag: ## Show the migrator's lag per topic (records on the source not yet copied)
	@./scripts/lag.sh

# tag::wait-lag[]
wait-lag: ## Wait until the migrator has copied every record (total lag 0)
	@for i in $$(seq 1 90); do \
	  lag=$$(./scripts/lag.sh --total 2>/dev/null || echo x); \
	  if [ "$$lag" = 0 ]; then echo "migrator lag is 0 on every topic"; exit 0; fi; \
	  sleep 2; \
	done; echo "migrator lag did not reach 0 in time (lag: $$lag)"; exit 1
# end::wait-lag[]

# tag::cutover[]
stop-consumer: .env ## Cutover 1: stop the consumer on the source; its committed offsets stand still
	$(COMPOSE) stop orders-consumer

wait-offsets: ## Cutover 2: wait until the migrator has written the same offsets for orders-service on the target
	@./scripts/wait-for-offsets.sh 120

consumer-target: .env ## Cutover 3: start the same consumer against the target; it resumes from the translated offsets
	$(COMPOSE) up -d orders-consumer-target

stop-producer: .env ## Cutover 4: stop the producer (in production: point it at the target)
	$(COMPOSE) stop producer

sr-readwrite: ## Cutover 5: return the target Schema Registry to READWRITE mode
	@$(RPK_TARGET) registry mode set --mode READWRITE

cutover: stop-consumer wait-offsets consumer-target stop-producer wait-lag sr-readwrite ## Run the five cutover steps in order
# end::cutover[]

seed: topics schemas migrator-access workload migrate schema-v2 cutover ## Run the whole migration path so that make verify can check the result

verify: ## Prove the outcome; prints PASS (n/n) or FAIL
	./scripts/verify.sh

logs: .env ## Follow the logs of every service
	$(COMPOSE) --profile '*' logs -f --tail=100

clean: .env ## Stop every service and delete the volumes
	$(COMPOSE) --profile '*' down -v --remove-orphans

test-docs: ## Run the Doc Detective specs for this solution (needs the repo checkout)
	@test -x ../../tools/run-doc-detective.sh || { echo "make test-docs needs the solutions repo checkout (tools/run-doc-detective.sh)"; exit 1; }
	../../tools/run-doc-detective.sh $(SLUG)
