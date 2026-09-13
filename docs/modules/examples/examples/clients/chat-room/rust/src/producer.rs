use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::util::Timeout;
use serde::{Deserialize, Serialize};
use std::time::Duration;

use crate::config::client_config;

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ChatMessage {
    pub user: String,
    pub message: String,
}

// tag::producer[]
pub struct ChatProducer {
    producer: FutureProducer,
    topic: String,
}

impl ChatProducer {
    pub fn new(topic: &str) -> Self {
        let producer: FutureProducer = client_config().create().expect("Producer creation failed");
        ChatProducer {
            producer,
            topic: topic.to_string(),
        }
    }

    /// Produce one JSON-encoded chat message, keyed by the user name.
    pub async fn send_message(&self, message: ChatMessage) {
        let payload = serde_json::to_string(&message).expect("Failed to serialize message");
        if let Err((err, _)) = self
            .producer
            .send(
                FutureRecord::to(&self.topic).payload(&payload).key(&message.user),
                Timeout::After(Duration::from_secs(5)),
            )
            .await
        {
            eprintln!("Failed to send message: {}", err);
        }
    }
}
// end::producer[]
