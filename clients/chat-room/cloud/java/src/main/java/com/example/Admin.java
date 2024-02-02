package com.example;

import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.clients.admin.AdminClientConfig;
import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.config.SaslConfigs;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import java.util.Collections;
import java.util.Properties;

public class Admin {
  private static final String BOOTSTRAP_SERVERS = "<bootstrap-server-address>";
  private static final String SASL_USERNAME = "redpanda-chat-account";
  private static final String SASL_PASSWORD = "<password>";
  public static Properties getProducerProps() {
    Properties props = getAdminProps();
    props.put("key.serializer", StringSerializer.class.getName());
    props.put("value.serializer", StringSerializer.class.getName());
    return props;
  }
  public static Properties getConsumerProps(String groupId) {
    Properties props = getAdminProps();
    props.put("group.id", groupId);
    props.put("key.deserializer", StringDeserializer.class.getName());
    props.put("value.deserializer", StringDeserializer.class.getName());
    return props;
  }
  public static boolean topicExists(String topicName) {
      Properties props = getAdminProps();
      try (AdminClient client = AdminClient.create(props)) {
        return client.listTopics().names().get().contains(topicName);
      } catch (Exception e) {
          throw new RuntimeException(e);
      }
  }
  public static void createTopic(String topicName) {
    Properties props = getAdminProps();
    try (AdminClient client = AdminClient.create(props)) {
      NewTopic newTopic = new NewTopic(topicName, 1, (short) 1);
      client.createTopics(Collections.singletonList(newTopic));
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }
  private static Properties getAdminProps() {
    Properties props = new Properties();
    props.put(AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, BOOTSTRAP_SERVERS);
    props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
    props.put(SaslConfigs.SASL_MECHANISM, "SCRAM-SHA-256");
    props.put(SaslConfigs.SASL_JAAS_CONFIG,
          "org.apache.kafka.common.security.scram.ScramLoginModule required username=\""
                  + SASL_USERNAME + "\" password=\"" + SASL_PASSWORD + "\";");
    return props;
  }
}