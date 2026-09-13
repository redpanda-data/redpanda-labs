import { KafkaJS } from "@confluentinc/kafka-javascript";

// tag::config[]
// Connection settings come from environment variables:
//   REDPANDA_BROKERS         comma-separated bootstrap servers (default localhost:19092)
//   REDPANDA_SASL_USERNAME   SASL/SCRAM user; when set, TLS and SASL are enabled
//   REDPANDA_SASL_PASSWORD   SASL/SCRAM password
//   REDPANDA_SASL_MECHANISM  scram-sha-256 (default) or scram-sha-512
export const topic = process.env.REDPANDA_TOPIC ?? "chat-room";

const brokers = (process.env.REDPANDA_BROKERS ?? "localhost:19092").split(",");
const username = process.env.REDPANDA_SASL_USERNAME;

const config: KafkaJS.KafkaConfig = { brokers };
if (username) {
  config.ssl = true;
  config.sasl = {
    mechanism: (process.env.REDPANDA_SASL_MECHANISM ?? "scram-sha-256").toLowerCase() as
      | "scram-sha-256"
      | "scram-sha-512",
    username,
    password: process.env.REDPANDA_SASL_PASSWORD ?? "",
  };
}

// The KafkaJS-compatible API of @confluentinc/kafka-javascript takes its
// options under the kafkaJS key.
export const redpanda = new KafkaJS.Kafka({ kafkaJS: config });
// end::config[]
