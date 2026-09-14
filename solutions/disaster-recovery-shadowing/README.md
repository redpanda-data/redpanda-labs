# Disaster Recovery with Shadowing and Envoy

Code for the Disaster Recovery with Shadowing and Envoy solution: two Redpanda
clusters, one shadow link that replicates topics and consumer group offsets,
and an Envoy proxy that is the only Kafka address clients hold, so a failover
needs no client change. The guided walkthrough lives on the docs site at
`/solutions/disaster-recovery-shadowing/`; this directory is what `make`
drives and what the download bundle contains.

## Run it

```bash
make up        # build the client image, start both clusters, Envoy, both Consoles, the rpk helpers, and the client
make seed      # the whole recovery path: topic, link, produce, consume, parity, outage, failover, resume
make verify    # prints PASS (23/23) when the recovery reached its end state
make clean     # stop everything, delete the volumes, drop the recorded state
```

`make help` lists every target, including the single steps the walkthrough
uses (`topic`, `link`, `status`, `endpoint`, `produce`, `consume`, `parity`,
`offsets`, `disaster`, `consume-during-disaster`, `produce-during-disaster`,
`failover`, `produce-after-failover`, `consume-after-failover`) and
`kubernetes-plan`, which checks the manifests in `kubernetes/`.

Versions and host ports are pinned in `.env` (copied from `.env.example` on
the first `make up`). The defaults leave the ports of the other solutions
free, so this stack can run next to them.

Then open (default ports):

| URL | What |
|---|---|
| http://localhost:8380 | Redpanda Console on the source cluster: the view the outage takes away |
| http://localhost:8381 | Redpanda Console on the shadow cluster: the replicated topics and consumer groups |
| http://localhost:60901 | Envoy's admin interface, including `/clusters` |
| `localhost:60092` | The Kafka endpoint Envoy serves. Clients inside the compose network use `envoy:9092`, because the Kafka broker filter rewrites broker addresses to that name. |

## Layout

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Two Redpanda clusters with Shadowing enabled, Envoy, one Console per cluster, one `rpk` helper per cluster, and the Python client |
| `Makefile` | `up`, `down`, `seed`, `verify`, `logs`, `clean`, `test-docs`, plus each step of the recovery |
| `config/shadow-link.yaml` | The shadow link: topic, consumer offset, and Schema Registry replication |
| `envoy/envoy.yaml` | The Kafka broker filter that rewrites broker addresses, and the two-priority endpoint list with health checks |
| `console/source.yaml`, `console/shadow.yaml` | One Console configuration per cluster |
| `client/` | The client image: Python with a pinned `kafka-python` |
| `sample-data/` | The 12 orders produced before the outage and the 6 produced after the failover |
| `scripts/produce.py`, `scripts/consume.py` | Produce and consume through Envoy, with `--expect` counts |
| `scripts/parity.py` | Compares the two clusters partition by partition and waits until they agree |
| `scripts/offsets.py` | Waits until the consumer group's committed offsets reach the shadow cluster |
| `scripts/endpoint.py` | What the client can see through Envoy, and which cluster Envoy is using |
| `scripts/state.py` | Reads one recorded fact back out of `state/` |
| `scripts/verify.sh` | End-to-end checks; CI gates on its exit code |
| `scripts/check-kubernetes.sh` | Checks the Kubernetes manifests and that they still match `config/shadow-link.yaml` |
| `kubernetes/` | The same two clusters and the same link as `Redpanda` and `ShadowLink` resources for the Redpanda Operator |
| `state/` | Facts each step records as it runs, asserted by `scripts/verify.sh` once the source cluster is gone. Git-ignored; `make clean` deletes them. |
| `steps/<step-id>/` | The commands and captured outputs each documented step shows |
| `tests/doc-detective/` | `_setup` and `_teardown`; the step specs are generated from the pages |

## The state directory

`scripts/verify.sh` runs at the end of the walkthrough, when the source
cluster has been stopped. Two of the three claims this solution makes were
only measurable earlier: that the clusters were at parity before the outage,
and that a client kept reading during it. Each step writes what it measured to
`state/<name>.json` at the moment it measured it, and `verify.sh` asserts
those recorded facts alongside what it can still measure live. `make clean`
deletes them, so a half-finished run cannot make a later `make verify` pass.

## Kubernetes

`kubernetes/` holds the same topology for the Redpanda Operator. The commands
that deploy it are on the `deploy-on-kubernetes` page and are not part of this
solution's test run; `make kubernetes-plan` is, and it is what keeps the
manifests and `config/shadow-link.yaml` describing the same link. See
`MIGRATION.md` for why.

## Docs

The pages under `docs/modules/disaster-recovery-shadowing/` in the repository
read this directory through symlinks: `include::example$...` shows code from
here, and the build-along files are published as attachments. Change code here
and the docs follow.
