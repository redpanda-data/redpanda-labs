# Chat room client (Rust)

Command-line chat room built on Redpanda with [rust-rdkafka](https://github.com/fede1024/rust-rdkafka).

Connection settings come from environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `REDPANDA_BROKERS` | `localhost:19092` | Comma-separated bootstrap servers |
| `REDPANDA_SASL_USERNAME` | unset | SASL/SCRAM user. Setting it turns on TLS and SASL (Redpanda Cloud) |
| `REDPANDA_SASL_PASSWORD` | unset | SASL/SCRAM password |
| `REDPANDA_SASL_MECHANISM` | `SCRAM-SHA-256` | `SCRAM-SHA-256` or `SCRAM-SHA-512` |
| `REDPANDA_TOPIC` | `chat-room` | Topic to chat on |

Run it in two or more terminals:

```bash
cargo run
```

Docs page: `streaming:develop:client-tutorials/chat-room.adoc`.
