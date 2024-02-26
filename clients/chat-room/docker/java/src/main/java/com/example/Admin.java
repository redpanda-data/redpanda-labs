package com.example;

import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.clients.admin.AdminClientConfig;
import java.util.Collections;
import java.util.Properties;
public class Admin {
  private final static String BOOTSTRAP_SERVERS = "localhost:19092";
  public static Properties getProducerProps() {
    Properties props = new Properties();
    props.put("bootstrap.servers", BOOTSTRAP_SERVERS);
    props.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
    props.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer");
    return props;
  }
  public static Properties getConsumerProps(String groupId) {
    Properties props = new Properties();
    props.put("bootstrap.servers", BOOTSTRAP_SERVERS);
    props.put("group.id", groupId);
    props.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
    props.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
    return props;
  }
  public static boolean topicExists(String topicName) {
    Properties props = new Properties();
    props.put(AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, BOOTSTRAP_SERVERS);
    try (AdminClient client = AdminClient.create(props)) {
      return client.listTopics().names().get().contains(topicName);
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }
  public static void createTopic(String topicName) {
    Properties props = new Properties();
    props.put(AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, BOOTSTRAP_SERVERS);
    try (AdminClient client = AdminClient.create(props)) {
      NewTopic newTopic = new NewTopic(topicName, 1, (short) 1);
      client.createTopics(Collections.singletonList(newTopic));
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }
}
