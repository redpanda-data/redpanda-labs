use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use tokio_stream::StreamExt;

use crate::config::client_config;
use crate::producer::ChatMessage;

// tag::consumer[]
/// Joins a new consumer group each run and reads from the beginning of the
/// topic, so every client sees the whole chat history.
pub struct ChatConsumer {
    consumer: StreamConsumer,
}

impl ChatConsumer {
    pub fn new(topic: &str, group_id: &str) -> Self {
        let consumer: StreamConsumer = client_config()
            .set("group.id", group_id)
            .set("auto.offset.reset", "earliest")
            .create()
            .expect("Consumer creation failed");
        consumer.subscribe(&[topic]).expect("Subscribing to topic failed");
        ChatConsumer { consumer }
    }

    pub async fn consume_messages(&self) {
        let mut stream = self.consumer.stream();
        while let Some(result) = stream.next().await {
            match result {
                Ok(message) => match message.payload_view::<str>() {
                    Some(Ok(payload)) => match serde_json::from_str::<ChatMessage>(payload) {
                        Ok(chat) => println!("{}: {}", chat.user, chat.message),
                        Err(e) => eprintln!("Error decoding message: {:?}", e),
                    },
                    _ => eprintln!("Message has no readable payload"),
                },
                Err(error) => eprintln!("Kafka error: {}", error),
            }
        }
    }
}
// end::consumer[]
