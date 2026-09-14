# Disaster Recovery with Shadowing and Envoy
#
# The targets below are the contract every solution keeps so that CI, the
# generated Doc Detective specs, and readers all drive the stack the same way.
# This solution adds the recovery itself: create the link, produce and consume
# through Envoy, prove parity, stop the source cluster, read through Envoy
# again, fail the link over, and produce on the shadow cluster.
SHELL := /bin/bash
.DEFAULT_GOAL := help
COMPOSE ?= docker compose
SLUG := disaster-recovery-shadowing
SOURCE := $(COMPOSE) exec -T rpk-source rpk
SHADOW := $(COMPOSE) exec -T rpk-shadow rpk
CLIENT := $(COMPOSE) exec -T client python3
# Read from .env when it exists, so a reader who changed a value there does not
# have to repeat it on the command line.
env = $(or $(shell sed -nE 's/^$(1)=(.+)$$/\1/p' .env 2>/dev/null),$(2))
LINK := $(call env,SHADOW_LINK,disaster-recovery-shadowing)
TOPIC := $(call env,DR_TOPIC,dr-orders)
PARTITIONS := $(call env,DR_PARTITIONS,3)
GROUP := $(call env,DR_GROUP,dr-consumers)

.PHONY: help up down seed verify logs clean test-docs \
        topic link status describe produce consume parity offsets endpoint \
        disaster consume-during-disaster produce-during-disaster \
        failover wait-failover produce-after-failover consume-after-failover \
        recover kubernetes-plan

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "  %-26s %s\n", $$1, $$2}'

.env:
	cp .env.example .env

up: .env ## Build the client image, start both clusters, Envoy, both Consoles, and the helpers; wait for every healthcheck
	$(COMPOSE) up -d --build --wait

down: .env ## Stop the services, keep data volumes
	$(COMPOSE) down

# tag::setup[]
topic: ## Create the replicated topic on the source cluster
	@$(SOURCE) topic create $(TOPIC) --partitions $(PARTITIONS) --replicas 1

link: ## Create the shadow link on the shadow cluster from config/shadow-link.yaml
	@$(SHADOW) shadow create --config-file /config/shadow-link.yaml --no-confirm

status: ## Show the link's state, its tasks, and every shadow topic
	@$(SHADOW) shadow status $(LINK) --print-topic

describe: ## Show the link's configuration as the cluster stored it
	@$(SHADOW) shadow describe $(LINK)
# end::setup[]

# tag::workload[]
endpoint: ## Show the client's view through Envoy, and which cluster Envoy is using
	@$(CLIENT) /scripts/endpoint.py

produce: ## Produce the 12 seed orders through Envoy
	@$(CLIENT) /scripts/produce.py /sample-data/orders.json --state produce-before

consume: ## Consume through Envoy as the dr-consumers group and commit the offsets
	@$(CLIENT) /scripts/consume.py --expect 12 --state consume-before

parity: ## Wait until both clusters hold the same records, partition by partition
	@$(CLIENT) /scripts/parity.py --expect 12 --state parity

offsets: ## Wait until the group's committed offsets reach the shadow cluster
	@$(CLIENT) /scripts/offsets.py --state offsets-before
# end::workload[]

# tag::disaster[]
disaster: ## Stop the source cluster and wait until Envoy takes it out of service
	@$(COMPOSE) stop redpanda-source
	@for i in $$(seq 1 30); do \
	  if $(CLIENT) /scripts/endpoint.py --routing-only --expect-routing shadow >/dev/null 2>&1; then break; fi; \
	  sleep 2; \
	done
	@echo "the source cluster is stopped"
	@$(CLIENT) /scripts/endpoint.py --routing-only --expect-routing shadow

consume-during-disaster: ## Read every replicated record through the same Envoy address, with the source gone
	@$(CLIENT) /scripts/consume.py --group observer-during-disaster --no-commit --expect 12 --state continuity

produce-during-disaster: ## Try to write while the shadow topic is still read-only (expected to be refused)
	@$(CLIENT) /scripts/produce.py /sample-data/orders-after-failover.json --expect-rejected --state refused-during-disaster
# end::disaster[]

# tag::failover[]
failover: ## Fail every shadow topic over: they stop replicating and become writable (irreversible)
	@$(SHADOW) shadow failover $(LINK) --all --no-confirm
	@$(MAKE) --no-print-directory wait-failover

wait-failover: ## Wait until every shadow topic reports FAILED_OVER
	@for i in $$(seq 1 60); do \
	  n=$$($(SHADOW) shadow status $(LINK) --print-topic 2>/dev/null </dev/null | grep -c 'State: FAILED_OVER'); \
	  if [ "$$n" -ge 1 ]; then $(SHADOW) shadow status $(LINK) --print-topic; exit 0; fi; \
	  sleep 2; \
	done; echo "the shadow topics did not reach FAILED_OVER in time"; \
	$(SHADOW) shadow status $(LINK) --print-topic; exit 1

produce-after-failover: ## Produce 6 more orders through the same Envoy address, now served by the shadow cluster
	@$(CLIENT) /scripts/produce.py /sample-data/orders-after-failover.json --state produce-after

consume-after-failover: ## Consume as the same group: it resumes from the replicated offsets
	@$(CLIENT) /scripts/consume.py --expect 6 --state consume-after
# end::failover[]

recover: topic link produce consume parity offsets disaster consume-during-disaster produce-during-disaster failover produce-after-failover consume-after-failover ## The whole recovery path

seed: recover ## Run the whole recovery path so that make verify can check the result

verify: ## Prove the outcome; prints PASS (n/n) or FAIL
	./scripts/verify.sh

# tag::kubernetes[]
kubernetes-plan: ## Print what the Kubernetes manifests in kubernetes/ would deploy
	@./scripts/check-kubernetes.sh
# end::kubernetes[]

logs: .env ## Follow the logs of every service
	$(COMPOSE) logs -f --tail=100

clean: .env ## Stop the services, delete their volumes, and drop the recorded state
	$(COMPOSE) down -v --remove-orphans
	@rm -f state/*.json

test-docs: ## Run the Doc Detective specs for this solution (needs the repo checkout)
	@test -x ../../tools/run-doc-detective.sh || { echo "make test-docs needs the solutions repo checkout (tools/run-doc-detective.sh)"; exit 1; }
	../../tools/run-doc-detective.sh $(SLUG)
