package com.example;

import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import com.google.gson.Gson;
import java.util.HashMap;
import java.util.Map;
public class ChatProducer implements AutoCloseable {
  private KafkaProducer<String, String> producer;
  private String topic;
  private Gson gson;
  public ChatProducer(String topic) {
    this.producer = new KafkaProducer<>(Admin.getProducerProps());
    this.topic = topic;
    this.gson = new Gson();
  }
  public void sendMessage(String user, String message) {
    Map<String, String> messageMap = new HashMap<>();
    messageMap.put("user", user);
    messageMap.put("message", message);
    String jsonMessage = gson.toJson(messageMap);
    producer.send(new ProducerRecord<>(topic, null, jsonMessage));
    producer.flush();
  }
  @Override
  public void close() {
    producer.close();
  }
}