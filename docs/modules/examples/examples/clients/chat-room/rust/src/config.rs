use rdkafka::config::ClientConfig;
use std::env;

// tag::config[]
/// Connection settings come from environment variables:
///
///   REDPANDA_BROKERS         comma-separated bootstrap servers (default localhost:19092)
///   REDPANDA_SASL_USERNAME   SASL/SCRAM user; when set, TLS and SASL are enabled
///   REDPANDA_SASL_PASSWORD   SASL/SCRAM password
///   REDPANDA_SASL_MECHANISM  SCRAM-SHA-256 (default) or SCRAM-SHA-512
pub fn client_config() -> ClientConfig {
    let mut config = ClientConfig::new();
    config.set(
        "bootstrap.servers",
        env::var("REDPANDA_BROKERS").unwrap_or_else(|_| "localhost:19092".to_string()),
    );
    if let Ok(username) = env::var("REDPANDA_SASL_USERNAME") {
        config
            .set("security.protocol", "SASL_SSL")
            .set(
                "sasl.mechanisms",
                env::var("REDPANDA_SASL_MECHANISM")
                    .unwrap_or_else(|_| "SCRAM-SHA-256".to_string())
                    .to_uppercase(),
            )
            .set("sasl.username", username)
            .set("sasl.password", env::var("REDPANDA_SASL_PASSWORD").unwrap_or_default());
    }
    config
}

pub fn topic() -> String {
    env::var("REDPANDA_TOPIC").unwrap_or_else(|_| "chat-room".to_string())
}
// end::config[]
