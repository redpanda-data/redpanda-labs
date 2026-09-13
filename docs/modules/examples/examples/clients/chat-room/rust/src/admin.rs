use rdkafka::admin::{AdminClient, AdminOptions, NewTopic, TopicReplication};
use rdkafka::client::DefaultClientContext;
use rdkafka::error::KafkaResult;
use rdkafka::util::Timeout;
use std::time::Duration;

use crate::config::client_config;

// tag::admin[]
pub struct Admin {
    client: AdminClient<DefaultClientContext>,
}

impl Admin {
    pub fn new() -> Self {
        let client: AdminClient<DefaultClientContext> = client_config()
            .create()
            .expect("Admin client creation error");
        Admin { client }
    }

    pub fn topic_exists(&self, topic: &str) -> KafkaResult<bool> {
        let metadata = self
            .client
            .inner()
            .fetch_metadata(None, Timeout::After(Duration::from_secs(10)))?;
        Ok(metadata.topics().iter().any(|t| t.name() == topic))
    }

    /// Create the topic with one partition and one replica.
    pub async fn create_topic(&self, topic: &str) -> KafkaResult<()> {
        let new_topic = NewTopic::new(topic, 1, TopicReplication::Fixed(1));
        let results = self
            .client
            .create_topics(
                &[new_topic],
                &AdminOptions::new().operation_timeout(Some(Timeout::After(Duration::from_secs(10)))),
            )
            .await?;
        for result in results {
            match result {
                Ok(_) => println!("Created topic {}", topic),
                Err((err, _)) => eprintln!("Failed to create topic {}: {:?}", topic, err),
            }
        }
        Ok(())
    }
}
// end::admin[]
