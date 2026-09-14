package com.example;

import com.google.gson.Gson;
import java.util.HashMap;
import java.util.Map;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;

// tag::producer[]
public class ChatProducer implements AutoCloseable {
  private final KafkaProducer<String, String> producer;
  private final String topic;
  private final Gson gson = new Gson();

  public ChatProducer(String topic) {
    this.producer = new KafkaProducer<>(Admin.getProducerProps());
    this.topic = topic;
  }

  /** Produce one JSON-encoded chat message. */
  public void sendMessage(String user, String message) {
    Map<String, String> messageMap = new HashMap<>();
    messageMap.put("user", user);
    messageMap.put("message", message);
    producer.send(new ProducerRecord<>(topic, null, gson.toJson(messageMap)));
    producer.flush();
  }
// end::producer[]

  @Override
  public void close() {
    producer.close();
  }
}
