package com.example;

import java.util.Properties;
import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.common.config.SaslConfigs;

// tag::config[]
/**
 * Connection settings come from environment variables:
 *
 * <pre>
 * REDPANDA_BROKERS         comma-separated bootstrap servers (default localhost:19092)
 * REDPANDA_SASL_USERNAME   SASL/SCRAM user; when set, TLS and SASL are enabled
 * REDPANDA_SASL_PASSWORD   SASL/SCRAM password
 * REDPANDA_SASL_MECHANISM  SCRAM-SHA-256 (default) or SCRAM-SHA-512
 * </pre>
 */
public class Config {
  public static final String TOPIC = env("REDPANDA_TOPIC", "chat-room");

  /** Properties shared by the admin client, producer, and consumer. */
  public static Properties clientProps() {
    Properties props = new Properties();
    props.put(CommonClientConfigs.BOOTSTRAP_SERVERS_CONFIG, env("REDPANDA_BROKERS", "localhost:19092"));

    String username = System.getenv("REDPANDA_SASL_USERNAME");
    if (username != null && !username.isEmpty()) {
      props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
      props.put(SaslConfigs.SASL_MECHANISM, env("REDPANDA_SASL_MECHANISM", "SCRAM-SHA-256").toUpperCase());
      props.put(SaslConfigs.SASL_JAAS_CONFIG,
          "org.apache.kafka.common.security.scram.ScramLoginModule required username=\""
              + username + "\" password=\"" + env("REDPANDA_SASL_PASSWORD", "") + "\";");
    }
    return props;
  }
// end::config[]

  static String env(String key, String fallback) {
    String value = System.getenv(key);
    return (value == null || value.isEmpty()) ? fallback : value;
  }
}
