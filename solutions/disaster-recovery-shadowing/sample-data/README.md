# Sample data

Two committed, deterministic sets of orders. `scripts/produce.py` reads one of
them and produces every record through Envoy, keyed by `order_id`, so the
partition each record lands on is the same on every run and the counts the
steps and `scripts/verify.sh` assert are exact.

| File | Records | Keys | Produced in |
|---|---|---|---|
| `orders.json` | 12 | `ord-0001` to `ord-0012` | Route clients through Envoy, while the source cluster is the writer |
| `orders-after-failover.json` | 6 | `ord-0013` to `ord-0018` | Fail over, once the shadow cluster accepts writes |

The two sets never overlap, so a duplicate or a missing record shows up as a
count that does not match.
