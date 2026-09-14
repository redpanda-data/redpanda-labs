package com.example;

import java.util.Collections;
import java.util.Properties;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;

// tag::admin[]
public class Admin {
  public static Properties getProducerProps() {
    Properties props = Config.clientProps();
    props.put("key.serializer", StringSerializer.class.getName());
    props.put("value.serializer", StringSerializer.class.getName());
    return props;
  }

  public static Properties getConsumerProps(String groupId) {
    Properties props = Config.clientProps();
    props.put("group.id", groupId);
    props.put("auto.offset.reset", "earliest");
    props.put("key.deserializer", StringDeserializer.class.getName());
    props.put("value.deserializer", StringDeserializer.class.getName());
    return props;
  }

  public static boolean topicExists(String topicName) {
    try (AdminClient client = AdminClient.create(Config.clientProps())) {
      return client.listTopics().names().get().contains(topicName);
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }

  /** Create the topic with one partition and one replica. */
  public static void createTopic(String topicName) {
    try (AdminClient client = AdminClient.create(Config.clientProps())) {
      NewTopic newTopic = new NewTopic(topicName, 1, (short) 1);
      client.createTopics(Collections.singletonList(newTopic)).all().get();
      System.out.println("Created topic " + topicName);
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }
}
// end::admin[]
