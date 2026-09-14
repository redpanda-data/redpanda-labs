# Chat room client (Java)

Command-line chat room built on Redpanda with the
[Apache Kafka Java client](https://central.sonatype.com/artifact/org.apache.kafka/kafka-clients).

Connection settings come from environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `REDPANDA_BROKERS` | `localhost:19092` | Comma-separated bootstrap servers |
| `REDPANDA_SASL_USERNAME` | unset | SASL/SCRAM user. Setting it turns on TLS and SASL (Redpanda Cloud) |
| `REDPANDA_SASL_PASSWORD` | unset | SASL/SCRAM password |
| `REDPANDA_SASL_MECHANISM` | `SCRAM-SHA-256` | `SCRAM-SHA-256` or `SCRAM-SHA-512` |
| `REDPANDA_TOPIC` | `chat-room` | Topic to chat on |

Build once, then run it in two or more terminals:

```bash
mvn clean package
mvn exec:java -Dexec.mainClass="com.example.Main"
```

Docs page: `streaming:develop:client-tutorials/chat-room.adoc`.
