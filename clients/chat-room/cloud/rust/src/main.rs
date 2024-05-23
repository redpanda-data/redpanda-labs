mod admin;
mod consumer;
mod producer;

use crate::consumer::ChatConsumer;
use crate::producer::ChatProducer;
use std::io::BufRead;
use tokio::io::{self, AsyncBufReadExt, BufReader};
use tokio::task;

#[tokio::main]
async fn main() {
    dotenv::dotenv().ok();

    println!("Initiating Redpanda Admin Client");

    let brokers =
        std::env::var("REDPANDA_BROKER").expect("REDPANDA_BROKER environment variable not set");
    let username =
        std::env::var("REDPANDA_USERNAME").expect("REDPANDA_USERNAME environment variable not set");
    let password =
        std::env::var("REDPANDA_PASSWORD").expect("REDPANDA_PASSWORD environment variable not set");
    let topic = "chat-room";

    let group_id = format!(
        "{}_{}",
        "chat_group",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs()
    );

    let admin = admin::Admin::new(&brokers, &username, &password);

    if let Ok(exists) = admin.topic_exists(topic).await {
        if exists {
            println!("Topic {} already exists", topic);
        } else if let Err(err) = admin.create_topic(topic).await {
            eprintln!("Failed to create topic {}: {:?}", topic, err);
        }
    } else {
        eprintln!("Failed to check if topic {} exists", topic);
    }

    let avatar_name = get_username();

    let consumer = ChatConsumer::new(&brokers, topic, &group_id, &username, &password);
    let producer = ChatProducer::new(&brokers, topic, &username, &password);

    let consumer_handle = tokio::task::spawn(async move {
        consumer.consume_messages().await;
    });

    let username_clone1 = avatar_name.clone();
    let producer_handle = task::spawn(async move {
        let stdin = BufReader::new(io::stdin());
        let mut lines = stdin.lines();
        while let Some(line) = lines.next_line().await.unwrap() {
            if line.is_empty() {
                continue;
            }
            let chat_message = producer::ChatMessage {
                username: username_clone1.clone(),
                message: line.trim().to_string(),
            };

            producer.send_message(chat_message).await;
        }
    });

    let _ = tokio::join!(consumer_handle, producer_handle);
}

fn get_username() -> String {
    println!("Please enter your username:");
    let stdin = std::io::stdin();
    let mut handle = stdin.lock();
    let mut username = String::new();
    handle
        .read_line(&mut username)
        .expect("Failed to read username");
    username.trim().to_string()
}
