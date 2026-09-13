# Sample data

Deterministic input for the produce script. Keep it small and commit it: CI
and `scripts/verify.sh` count on exact numbers (three orders, two customers,
one shipment before cutover; one more order after).

| File | Loaded by | Topic | Subject |
|---|---|---|---|
| `orders.json` | `make produce` | `orders` | `orders-value` (Avro, version 2) |
| `customers.json` | `make produce` | `customers` | `customers-value` (Avro) |
| `shipping.json` | `make produce` | `shipping` | `shipping-value` (Avro, references `address-value`) |
| `orders-after-cutover.json` | `make produce-redpanda` | `orders` on the Redpanda cluster | `orders-value`, resolved from the Redpanda Schema Registry |

The schemas themselves live in `../schemas/` and are registered on the source
Confluent Schema Registry by `make register-schemas` and
`make register-complex-schemas`.
