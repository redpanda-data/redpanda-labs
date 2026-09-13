# Chat room client (Python)

Command-line chat room built on Redpanda with [kafka-python](https://github.com/dpkp/kafka-python).

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
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python3 app.py
```

Docs page: `streaming:develop:client-tutorials/chat-room.adoc`.
