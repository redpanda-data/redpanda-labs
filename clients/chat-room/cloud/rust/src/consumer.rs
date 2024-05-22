use rdkafka::config::ClientConfig;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use serde::{Deserialize, Serialize};
use tokio_stream::StreamExt;

#[derive(Serialize, Deserialize, Debug)]
pub struct ChatMessage {
    pub username: String,
    pub message: String,
}

pub struct ChatConsumer {
    consumer: StreamConsumer,
}

impl ChatConsumer {
    pub fn new(broker: &str, topic: &str, group_ir: &str, username: &str, password: &str) -> Self {
        let consumer: StreamConsumer = ClientConfig::new()
            .set("bootstrap.servers", broker)
            .set("group.id", group_ir)
            .set("auto.offset.reset", "earliest")
            .set("security.protocol", "SASL_SSL")
            .set("sasl.mechanisms", "SCRAM-SHA-256")
            .set("sasl.username", username)
            .set("sasl.password", password)
            .create()
            .expect("Consumer creation failed");

        consumer
            .subscribe(&[topic])
            .expect("Subscribing to topic failed");

        ChatConsumer { consumer }
    }

    pub async fn consume_messages(&self) {
        let mut stream = self.consumer.stream();

        while let Some(result) = stream.next().await {
            match result {
                Ok(message) => {
                    let payload = match message.payload_view::<str>() {
                        Some(Ok(payload)) => payload,
                        Some(Err(e)) => {
                            eprintln!("Error while deserializing message payload: {:?}", e);
                            continue;
                        }
                        None => {
                            eprintln!("Failed to get message payload");
                            continue;
                        }
                    };

                    match serde_json::from_str::<ChatMessage>(payload) {
                        Ok(chat_message) => {
                            let message =
                                format!("{}: {}", chat_message.username, chat_message.message);
                            println!("{}", message);
                        }
                        Err(e) => {
                            eprintln!("Error while deserializing message payload: {:?}", e);
                            continue;
                        }
                    }
                }
                Err(error) => {
                    eprintln!("Kafka error: {}", error);
                }
            }
        }
    }
}
