use rdkafka::config::ClientConfig;
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::util::Timeout;
use serde::{Deserialize, Serialize};
use std::time::Duration;

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ChatMessage {
    pub username: String,
    pub message: String,
}

pub struct ChatProducer {
    producer: FutureProducer,
    topic: String,
}

impl ChatProducer {
    pub fn new(brokers: &str, topic: &str, username: &str, password: &str) -> Self {
        let producer: FutureProducer = ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("security.protocol", "SASL_SSL")
            .set("sasl.mechanisms", "SCRAM-SHA-256")
            .set("sasl.username", username)
            .set("sasl.password", password)
            .create()
            .expect("Producer creation failed");

        ChatProducer {
            producer,
            topic: topic.to_string(),
        }
    }

    pub async fn send_message(&self, message: ChatMessage) {
        let payload = serde_json::to_string(&message).expect("Failed to serialize message");

        self.producer
            .send(
                FutureRecord::to(&self.topic)
                    .payload(&payload)
                    .key(&message.username),
                Timeout::After(Duration::from_secs(0)),
            )
            .await
            .unwrap();
    }
}
