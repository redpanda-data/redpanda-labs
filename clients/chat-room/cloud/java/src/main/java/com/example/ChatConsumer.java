package com.example;

import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import java.lang.reflect.Type;
import java.util.Map;
import java.time.Duration;
import java.util.Collections;

public class ChatConsumer implements Runnable, AutoCloseable {
  private volatile boolean running = true;
  private KafkaConsumer<String, String> consumer;
  private Gson gson;
  private Type type;
  public ChatConsumer(String topic, String groupId) {
    this.consumer = new KafkaConsumer<>(Admin.getConsumerProps(groupId));
    this.consumer.subscribe(Collections.singletonList(topic));
    this.gson = new Gson();
    this.type = new TypeToken<Map<String, String>>(){}.getType();
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
  @Override
  public void close() {
    running = false;
    consumer.close();
  }
}