# Chat room client (Node.js)

Command-line chat room built on Redpanda with
[`@confluentinc/kafka-javascript`](https://github.com/confluentinc/confluent-kafka-javascript)
through its KafkaJS-compatible API.

Connection settings come from environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `REDPANDA_BROKERS` | `localhost:19092` | Comma-separated bootstrap servers |
| `REDPANDA_SASL_USERNAME` | unset | SASL/SCRAM user. Setting it turns on TLS and SASL (Redpanda Cloud) |
| `REDPANDA_SASL_PASSWORD` | unset | SASL/SCRAM password |
| `REDPANDA_SASL_MECHANISM` | `scram-sha-256` | `scram-sha-256` or `scram-sha-512` |
| `REDPANDA_TOPIC` | `chat-room` | Topic to chat on |

Build once, then run it in two or more terminals:

```bash
npm install
npm run build
npm start
```

Docs page: `streaming:develop:client-tutorials/chat-room.adoc`.
