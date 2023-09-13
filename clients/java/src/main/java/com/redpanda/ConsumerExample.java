package com.redpanda;

import java.time.Duration;
import java.util.Collections;
import java.util.Properties;

import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;

public class ConsumerExample {
    public static void main(String[] args) {
        Properties props = ClientConfig.consumerConfig();
        KafkaConsumer<Object, Object> consumer = new KafkaConsumer<>(props);
        consumer.subscribe(Collections.singletonList("test"));
        consumer.seekToBeginning(consumer.assignment());

        try {
            while (true) {
                ConsumerRecords<Object, Object> records = consumer.poll(Duration.ofSeconds(10));
                if (records.count() == 0) {
                    System.out.println("No more records");
                    break;
                }
                records.forEach(record -> {
                    System.out.printf("Consumed record: %s\n", record.toString());
                });
            }
        } catch(Exception e) {
            System.out.println(e);
        } finally {
            consumer.close();
        }
    }
}