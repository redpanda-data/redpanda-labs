# Migration note: two labs to one solution

This solution promotes the Redpanda Labs lab
`docker-compose/envoy-shadowing` (published as
`/labs/docker-compose/envoy-shadowing/`, source page
`labs-docs/modules/docker-compose/pages/envoy-shadowing.adoc`, a symlink to
the lab's `README.adoc`) and merges the Kubernetes lab
`kubernetes/shadow-linking` (published as
`/labs/kubernetes/shadow-linking/`, source page
`labs-docs/modules/kubernetes/pages/shadow-linking.adoc`) into it as the last
step, `deploy-on-kubernetes`.

Both lab directories are left untouched, and both labs pages keep building
from them until the decommission wave. This solution was built from copies,
rewritten to the solution contract.

## Kept from `docker-compose/envoy-shadowing`

- The architecture: two Redpanda clusters with `enable_shadow_linking=true`,
  one shadow link created on the shadow cluster, and an Envoy `contrib` image
  in front of both with the Kafka broker filter rewriting broker addresses and
  a two-priority endpoint list.
- The Envoy configuration's shape: `id_based_broker_address_rewrite_spec` for
  broker 0, an HTTP health check against each cluster's Schema Registry port,
  and `healthy_panic_threshold: 0.0` so that Envoy never spreads traffic
  across an unhealthy cluster.
- The shadow link's topic filter as a prefix filter, `start_at_earliest`, and
  `synced_shadow_topic_properties`.
- The failure drill: stop the source container, read through the same Envoy
  address, then `rpk shadow failover --all` to make the shadow cluster
  writable, then produce again through the same address.
- `kafka-python` as the client library. The lab's note that it is the client
  that works through Envoy turned out to be the load-bearing detail: newer
  clients negotiate request versions that the filter does not rewrite.

## Kept from `kubernetes/shadow-linking`

- The two-namespace topology (`source` and `shadow`), one `Redpanda` resource
  per namespace with `enable_shadow_linking: true` and
  `default_topic_replications: 1`, and external listeners advertised on
  `19094` and `29094` for `kubectl port-forward`.
- The `ShadowLink` resource with its `topicMetadataSyncOptions`,
  `consumerOffsetSyncOptions`, and `schemaRegistrySyncOptions`, and the
  in-cluster DNS names that join the two namespaces.
- The consumer group failover drill, which is the part of that lab this
  solution is built around: produce, consume as a group, fail over, and
  resume.
- cert-manager and the Redpanda Operator installed with Helm, and the `rpk`
  profile pair for reaching both clusters from the host.

## Rewritten

- **One story instead of two.** The compose lab stopped at "produce new
  messages to the failed-over cluster" and the Kubernetes lab explored three
  unrelated features (topic shadowing, Schema Registry shadowing, consumer
  group failover). The solution has one claim, that a failover costs a
  reconnect, and every step proves a part of it.
- **Consumer group offsets are now the point, not a section.** The compose lab
  replicated offsets (`consumer_offset_sync_options` with a `*` group filter)
  and never used them: its producer and consumer had no group. The solution
  consumes as `dr-consumers` before the outage and resumes as `dr-consumers`
  after the failover, and `scripts/verify.sh` asserts the resumed offsets
  equal the replicated ones.
- **Group and topic filters are prefixes.** The labs used `*` for groups and
  `demo-` or `*` for topics. Both filters are now the `dr-` prefix, which
  makes the recovery scope an explicit decision and lets the walkthrough use a
  group outside the filter (`observer-during-disaster`) to read during the
  outage without the link touching its offsets.
- **The client scripts are deterministic and assert their own results.**
  `test-producer.py` and `test-consumer.py` printed `OK` and a count. They are
  now `produce.py`, `consume.py`, `parity.py`, `offsets.py`, and `endpoint.py`,
  they read committed sample data (12 orders, then 6 more), they take
  `--expect` counts, and they record what they measured into `state/` so that
  `scripts/verify.sh` can assert facts that stopped being measurable once the
  source cluster was gone.
- **The client is a built image** (`client/Dockerfile` with a pinned
  `kafka-python`) instead of `pip install kafka-python` at container start, so
  the stack is reproducible and `make up --wait` means something.
- **Envoy's view is read from Envoy.** The lab asserted "Envoy detects the
  failure in 10-15 seconds" in prose. `endpoint.py` reads
  `/clusters?format=json` from Envoy's admin API and reports the state of each
  priority, and `make disaster` blocks until Envoy says it is routing to the
  shadow cluster, so the timing is waited for rather than claimed.
- **Two Consoles instead of none.** The compose lab had no Console. One
  Console per cluster makes the replication visible and gives the outage
  something to take away.
- **Ports moved** so the stack can run next to the other solutions. The
  compose lab used `9092`, `19092`, `29092`, `18081`, `28081`, and `9901`,
  which collide with the flagship and the schema-registry-migration stacks.

  | Port | What | `.env` variable |
  |---|---|---|
  | `60092` | The Kafka endpoint Envoy serves | `ENVOY_KAFKA_PORT` |
  | `60901` | Envoy's admin interface | `ENVOY_ADMIN_PORT` |
  | `63092`, `63081`, `63644` | Source cluster: Kafka, Schema Registry, Admin API | `SOURCE_KAFKA_PORT`, `SOURCE_SR_PORT`, `SOURCE_ADMIN_PORT` |
  | `61092`, `61081`, `61644` | Shadow cluster: Kafka, Schema Registry, Admin API | `SHADOW_KAFKA_PORT`, `SHADOW_SR_PORT`, `SHADOW_ADMIN_PORT` |
  | `8380`, `8381` | Redpanda Console, source and shadow | `SOURCE_CONSOLE_PORT`, `SHADOW_CONSOLE_PORT` |

  None of these collide with the ports the other solutions hold: Consoles
  `8080`, `8180`, `8280`, `8480`; Kafka `19092`, `29092`, `39092`, `49092`,
  `59092`, `64092`; Schema Registry `18081`, `28081`, `38081`, `48081`,
  `58081`, `64081`; Postgres `5432` and `5433`; MySQL `3307`; MinIO `9100`
  and `9101`; Iceberg REST `8581`; Spark `4041`; Redpanda Connect `4195` and
  `4196`.

  The ports this migration was briefed with, Kafka `69092` and Schema
  Registry `68081`, are above the 65535 limit of a TCP port and cannot be
  bound, so the source cluster took `63092` and `63081` instead.
- **Container names are prefixed with the slug** and the compose project is
  named, so two solutions can be up at once.
- **Versions are pinned** (`REDPANDA_VERSION=v26.2.2`,
  `REDPANDA_CONSOLE_VERSION=v3.11.0`) instead of the lab's `v25.3.4`, and the
  Kubernetes manifests match, with the Redpanda Operator at `v26.2.3` and
  cert-manager at `v1.21.2` rather than the lab's unpinned cert-manager and
  operator `v25.3.1`.
- **The Kubernetes setup script is gone.** `setup.sh` hid every command behind
  `> /dev/null 2>&1`, so a reader learned nothing and a failure said nothing.
  Its steps are now the page's commands, in order, with the manifests applied
  by `kubectl apply -f` from files the reader can read.
- **`rpk` runs in helper containers** (`rpk-source`, `rpk-shadow`) with
  `RPK_BROKERS` and `RPK_ADMIN_HOSTS` set, so the compose walkthrough needs no
  host `rpk` and no repeated `-X admin.hosts=...` flags. The lab used
  `docker exec redpanda-shadow rpk ... -X admin.hosts=redpanda-shadow:9644` on
  every line.
- **`make` drives everything**, and the walkthrough is seven step pages with
  generated Doc Detective specs and captured expected outputs instead of one
  README with inline test comments.

## Added

- `scripts/verify.sh` with 23 assertions (`PASS (23/23)`), covering
  replication parity before the outage, client continuity through Envoy during
  it, and the consumer group resuming on the shadow cluster after the
  failover.
- The refused write. `make produce-during-disaster` shows that a shadow topic
  answers `PolicyViolationError` while the link is active, which is the reason
  a proxy can move clients before a human decides to promote anything. Neither
  lab showed it.
- `scripts/check-kubernetes.sh`, which reads the Kubernetes manifests, prints
  what they would deploy, and checks that their filters still match
  `config/shadow-link.yaml`. It is the one command of the Kubernetes step that
  runs on every test pass, so the two copies of the same link cannot drift
  apart unnoticed.
- An architecture diagram, a Production considerations table, and two Console
  screenshots captured by the test run.

## Dropped

- The `git clone` instructions and the GitHub repository links. The solutions
  repository may be private; readers use the attachments or the signed-in
  download.
- `ifdef::env-site`/`env-github` conditionals, the `:learning-objective-N:`
  attributes, and the "What you explored" section. The outcomes list on the
  overview replaces the last two.
- The Kubernetes lab's Schema Registry section (registering an Avro schema and
  consuming decoded records on the shadow cluster). Schema replication is
  still configured and the `_schemas` shadow topic is visible in
  `make status`, but the walkthrough does not teach the wire format: that is
  what the `schema-registry-migration` solution is for, and
  `:page-solution-related-solutions:` points at it.
- `scripts/setup-shadow-link.sh`, whose two commands are now `make topic` and
  `make link`.
- The broker `rack`. Naming each cluster with a rack would have let the client
  name the cluster it reached from Kafka metadata, but Envoy's Kafka broker
  filter (`contrib-v1.31`) resets the connection when a Metadata v1 response
  carries a non-null `rack`, so the clusters are named with `cluster_id`
  instead, which only `rpk` and Console read, and the client reports Envoy's
  routing decision from Envoy's admin API.

## Why the Kubernetes step's commands are marked `[.manual]`

Every command of `deploy-on-kubernetes` except the manifest check carries the
`[.manual]` role, so the generated Doc Detective spec skips it. Three reasons,
in order of weight:

1. **It cannot share the pass with the compose stack.** The step specs run in
   `:page-solution-steps:` order against one stack that `_setup` brings up and
   `_teardown` takes down, so by the time this step runs, two Redpanda
   clusters, two Consoles, Envoy, two `rpk` helpers, and the client are up. A
   kind cluster with cert-manager, the Redpanda Operator, and two more
   Redpanda clusters on top of that needs several more gigabytes and about
   fifteen minutes, which is most of the 45-minute CI budget for the whole
   solution.
2. **The failure modes are not this solution's.** A kind cluster that cannot
   pull an image, an operator whose CRDs are still reconciling, or a
   `kubectl port-forward` that dies would fail the solution's test run for
   reasons that have nothing to do with Shadowing or Envoy.
3. **`kubectl port-forward` and `kill %1 %2` are interactive.** They manage
   background jobs of the reader's shell, which a generated `runShell` step
   cannot reproduce faithfully.

What is tested instead is the thing that actually rots: the manifests.
`make kubernetes-plan` runs on every pass and fails when a manifest loses a
field the walkthrough relies on, when a `patternType` is not one the operator
accepts, or when the Kubernetes link and the compose link stop describing the
same replication.

That check exists because of a bug it would have caught. The manifests were
also validated field by field against the `ShadowLink` CRD of Redpanda
Operator v26.2.3, and the CRD's `NameFilter` accepts `literal` or `prefixed`
only: the `prefix` this migration first wrote, which reads more naturally and
matches nothing, would have been rejected at `kubectl apply` time and never
in CI.

The step was then run once by hand, end to end, on a kind cluster: cert-manager
v1.21.2, Redpanda Operator v26.2.3, both `Redpanda` resources reaching
`condition=Ready`, the `ShadowLink` reaching `condition=Synced` with
`state: active`, 12 records and the `dr-consumers` group replicated to the
shadow cluster with lag 0, `rpk shadow failover` reaching `FAILED_OVER`, and
the same group reading exactly the 6 records produced after the failover. Two
commands were corrected from what that run showed: the link step now waits on
the `Synced` condition, and the port forwards write their process ids to a
file instead of relying on `kill %1 %2` finding the reader's shell jobs.

## Redirects and aliases at decommission

No `:page-aliases:` is set on any page in this solution yet: Antora throws
while a page with the alias target's id still exists, and both labs pages are
still in the build. At the retirement flip, add both aliases to
`docs/modules/disaster-recovery-shadowing/pages/index.adoc`, on one line:

```
:page-aliases: labs:docker-compose:envoy-shadowing.adoc, labs:kubernetes:shadow-linking.adoc
```

The merged lab's page becomes a redirect to the solution's overview rather
than to the step, because its content is spread across the whole solution and
only its last third became `deploy-on-kubernetes`. The `netlify.toml` rules,
for `docs-site`:

| From | To | Note |
|---|---|---|
| `/labs/docker-compose/envoy-shadowing/*` | `/solutions/disaster-recovery-shadowing/` | 301, promoted lab |
| `/labs/kubernetes/shadow-linking/*` | `/solutions/disaster-recovery-shadowing/` | 301, merged lab; the overview, not the step, because the lab covered the whole topology |
| `/redpanda-labs/docker-compose/envoy-shadowing/*` | `/solutions/disaster-recovery-shadowing/` | 301, the pre-rename URL twin |
| `/redpanda-labs/kubernetes/shadow-linking/*` | `/solutions/disaster-recovery-shadowing/` | 301, the pre-rename URL twin |

Add all four URLs to `docs-site/solutions/labs-urls.txt` so that
`scripts/solutions/check-redirects.mjs` covers them, and add the
`deploy-on-kubernetes` step URL as the place a reader of the old Kubernetes
lab is pointed to from the overview.

Then delete `docker-compose/envoy-shadowing/`, `kubernetes/shadow-linking/`,
and the two `labs-docs/modules/*/pages/*.adoc` symlinks.

## Product Docs follow-ups found while building this

1. `streaming:deploy:deployment-option/self-hosted/kubernetes/index.adoc`,
   which the Kubernetes lab linked, no longer exists. The page is now
   `streaming:deploy:redpanda/kubernetes/index.adoc`. Any other lab or page
   still using the old resource id needs the same correction.
2. The Shadowing documentation does not describe the error a produce request
   to an active shadow topic returns. It is `POLICY_VIOLATION`, and knowing it
   is what tells an operator that a client reached the failover cluster before
   the promotion. Worth a line in
   `streaming:manage:disaster-recovery/shadowing/failover.adoc`.
3. There is no guidance on the client-routing half of a failover: how clients
   are moved to the shadow cluster, and why that move is safe before the
   promotion. `failover-runbook.adoc` covers the promotion and the decision
   but leaves the reader to work out the DNS, load balancer, or proxy change
   themselves.
