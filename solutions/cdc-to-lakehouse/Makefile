# CDC to lakehouse
#
# The targets below are the contract every solution keeps so that CI, the
# Doc Detective specs, and readers all drive the stack the same way. This
# solution adds the pipeline itself: enable the Iceberg topic, start a change
# data capture pipeline against Postgres or MySQL, change some rows, and query
# the result through Spark.
SHELL := /bin/bash
.DEFAULT_GOAL := help
COMPOSE ?= docker compose
SLUG := cdc-to-lakehouse
TOPIC := cdc_orders
SUBJECT := $(TOPIC)-value
RPK := $(COMPOSE) exec -T rpk rpk

# Read .env so the database and object store names match whatever the reader
# set there. Only when it exists: the .env target below creates it.
ifneq (,$(wildcard .env))
include .env
export
endif
POSTGRES_USER ?= pandashop
POSTGRES_DB ?= pandashop
MYSQL_DATABASE ?= pandashop
MYSQL_ROOT_PASSWORD ?= pandashop-root
PSQL := $(COMPOSE) exec -T postgres psql -q -U $(POSTGRES_USER) -d $(POSTGRES_DB)
MYSQL_CLI := $(COMPOSE) exec -T mysql mysql -u root -p$(MYSQL_ROOT_PASSWORD) --silent $(MYSQL_DATABASE)

.PHONY: help up down seed verify logs clean test-docs \
        topic schema describe-topic license-check \
        cdc-postgres cdc-mysql cdc-logs consume changes \
        query-tables query-columns query-changes query-current query-freshness \
        wait-lakehouse lakehouse-count dlq

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "  %-18s %s\n", $$1, $$2}'

.env:
	cp .env.example .env

up: .env ## Build the Spark image, start every service, wait until all healthchecks pass
	$(COMPOSE) up -d --build --wait

down: .env ## Stop the services, keep data volumes
	$(COMPOSE) down

# tag::iceberg[]
topic: ## Create the cdc_orders topic with Iceberg writes turned on
	@$(RPK) topic create $(TOPIC) -p 1 -r 1 \
	  --topic-config=redpanda.iceberg.mode=value_schema_latest \
	  --topic-config=redpanda.iceberg.invalid.record.action=dlq_table

schema: ## Register the JSON schema that gives the Iceberg table its columns
	@$(RPK) registry schema create $(SUBJECT) --schema /schemas/order-change.json

describe-topic: ## Show the topic's Iceberg configuration
	@$(RPK) topic describe $(TOPIC) -c | grep -E 'KEY|redpanda.iceberg'

seed: topic schema ## Everything the lakehouse side needs before the first change arrives
# end::iceberg[]

# tag::cdc[]
license-check: ## Fail early when no Redpanda Connect license is set
	@set -a; [ -f .env ] && . ./.env; set +a; \
	if [ -z "$${REDPANDA_LICENSE:-}" ]; then \
	  echo "The postgres_cdc and mysql_cdc inputs are enterprise components."; \
	  echo "Put a trial or Enterprise Edition license key in REDPANDA_LICENSE in .env, then run this again."; \
	  exit 1; \
	fi

cdc-postgres: license-check ## Start the Postgres change data capture pipeline
	$(COMPOSE) up -d --wait connect-postgres

cdc-mysql: license-check ## Start the MySQL change data capture pipeline
	$(COMPOSE) up -d --wait connect-mysql

cdc-logs: ## Follow the change data capture pipeline logs
	$(COMPOSE) logs -f --tail=50 connect-postgres connect-mysql

changes: ## Apply one insert, one update, and one delete to the Postgres orders table
	@./scripts/change-orders.sh
# end::cdc[]

# tag::inspect[]
consume: ## Print the change events currently in the topic
	@$(RPK) topic consume $(TOPIC) --offset start --num $(or $(NUM),20) -f '%v\n'

dlq: ## Show whether Redpanda created a dead-letter table for records it could not translate
	@if ./scripts/lakehouse.sh query tables | grep -q '$(TOPIC)~dlq'; then \
	  echo "dead-letter table $(TOPIC)~dlq exists: some records failed to translate"; \
	else \
	  echo "no dead-letter table: every record translated"; \
	fi
# end::inspect[]

# tag::query[]
query-tables: ## List the Iceberg tables Redpanda registered in the catalog
	@./scripts/lakehouse.sh query tables

query-columns: ## Show the Iceberg table's columns, derived from the registered schema
	@./scripts/lakehouse.sh query columns

query-changes: ## Show every change row in the lakehouse
	@./scripts/lakehouse.sh query changes

query-current: ## Reconstruct the current state of the orders table from the change log
	@./scripts/lakehouse.sh query current

query-freshness: ## Show the change count and newest change per source database
	@./scripts/lakehouse.sh query freshness

lakehouse-count: ## Print the number of change rows in the Iceberg table
	@./scripts/lakehouse.sh count

wait-lakehouse: ## Wait until the Iceberg table holds ROWS rows (default 8)
	@./scripts/lakehouse.sh wait $(or $(ROWS),8)
# end::query[]

verify: ## Prove the outcome; prints PASS (n/n) or FAIL
	./scripts/verify.sh

logs: .env ## Follow the logs of every service
	$(COMPOSE) logs -f --tail=100

clean: .env ## Stop the services and delete their volumes
	$(COMPOSE) --profile postgres-cdc --profile mysql-cdc down -v --remove-orphans

test-docs: ## Run the Doc Detective specs for this solution (needs the repo checkout)
	@test -x ../../tools/run-doc-detective.sh || { echo "make test-docs needs the solutions repo checkout (tools/run-doc-detective.sh)"; exit 1; }
	../../tools/run-doc-detective.sh $(SLUG)
