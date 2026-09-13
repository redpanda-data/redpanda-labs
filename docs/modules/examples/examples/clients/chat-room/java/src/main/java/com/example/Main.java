package com.example;

import java.util.Scanner;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

// tag::main[]
public class Main {
  public static void main(String[] args) {
    String topic = Config.TOPIC;
    if (!Admin.topicExists(topic)) {
      Admin.createTopic(topic);
    }

    Scanner scanner = new Scanner(System.in);
    System.out.print("Enter your username: ");
    String username = scanner.nextLine();

    ExecutorService executorService = Executors.newSingleThreadExecutor();
    try (ChatConsumer consumer = new ChatConsumer(topic, UUID.randomUUID().toString());
        ChatProducer producer = new ChatProducer(topic)) {
      Future<?> future = executorService.submit(consumer);
      System.out.println("Connected, press Ctrl+C to exit");
      while (!future.isDone() && scanner.hasNextLine()) {
        String message = scanner.nextLine();
        if (!message.trim().isEmpty()) {
          producer.sendMessage(username, message);
        }
      }
    } catch (Exception e) {
      System.out.println("Closing chat...");
    } finally {
      executorService.shutdownNow();
    }
  }
}
// end::main[]
