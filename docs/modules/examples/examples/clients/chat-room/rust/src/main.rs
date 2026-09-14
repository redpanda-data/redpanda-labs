mod admin;
mod config;
mod consumer;
mod producer;

use crate::consumer::ChatConsumer;
use crate::producer::{ChatMessage, ChatProducer};
use std::io::BufRead;
use tokio::io::{self, AsyncBufReadExt, BufReader};

// tag::main[]
#[tokio::main]
async fn main() {
    let topic = config::topic();
    let group_id = format!(
        "chat_group_{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs()
    );

    let admin = admin::Admin::new();
    match admin.topic_exists(&topic) {
        Ok(true) => {}
        Ok(false) => {
            if let Err(err) = admin.create_topic(&topic).await {
                eprintln!("Failed to create topic {}: {:?}", topic, err);
            }
        }
        Err(err) => eprintln!("Failed to check if topic {} exists: {:?}", topic, err),
    }

    let username = get_username();
    let consumer = ChatConsumer::new(&topic, &group_id);
    let producer = ChatProducer::new(&topic);

    let consumer_handle = tokio::spawn(async move { consumer.consume_messages().await });
    println!("Connected. Press Ctrl+C to exit");
    let producer_handle = tokio::spawn(async move {
        let mut lines = BufReader::new(io::stdin()).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            if line.trim().is_empty() {
                continue;
            }
            producer
                .send_message(ChatMessage {
                    user: username.clone(),
                    message: line.trim().to_string(),
                })
                .await;
        }
    });

    let _ = tokio::join!(consumer_handle, producer_handle);
}
// end::main[]

fn get_username() -> String {
    println!("Enter your username:");
    let mut username = String::new();
    std::io::stdin()
        .lock()
        .read_line(&mut username)
        .expect("Failed to read username");
    username.trim().to_string()
}
