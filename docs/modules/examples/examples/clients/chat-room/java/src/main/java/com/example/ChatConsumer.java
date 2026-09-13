package com.example;

import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import java.lang.reflect.Type;
import java.time.Duration;
import java.util.Collections;
import java.util.Map;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;

// tag::consumer[]
/**
 * Joins a new consumer group each run and reads from the beginning of the
 * topic, so every client sees the whole chat history.
 */
public class ChatConsumer implements Runnable, AutoCloseable {
  private volatile boolean running = true;
  private final KafkaConsumer<String, String> consumer;
  private final Gson gson = new Gson();
  private final Type type = new TypeToken<Map<String, String>>() {}.getType();

  public ChatConsumer(String topic, String groupId) {
    this.consumer = new KafkaConsumer<>(Admin.getConsumerProps(groupId));
    this.consumer.subscribe(Collections.singletonList(topic));
  }

  @Override
  public void run() {
    while (running) {
      ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(1000));
      for (ConsumerRecord<String, String> record : records) {
        Map<String, String> messageMap = gson.fromJson(record.value(), type);
        System.out.println(messageMap.get("user") + ": " + messageMap.get("message"));
      }
    }
  }
// end::consumer[]

  @Override
  public void close() {
    running = false;
    consumer.wakeup();
  }
}
