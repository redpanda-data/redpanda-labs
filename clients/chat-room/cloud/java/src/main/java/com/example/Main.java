package com.example;
import java.util.Scanner;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Future;

public class Main {
  private static final String TOPIC = "chat-room";
  public static void main(String[] args) {
    if (!Admin.topicExists(TOPIC)) {
      Admin.createTopic(TOPIC);
    }
    Scanner scanner = new Scanner(System.in);
    System.out.print("Enter your username: ");
    String username = scanner.nextLine();
    ExecutorService executorService = Executors.newSingleThreadExecutor();
    try (ChatConsumer consumer = new ChatConsumer(TOPIC, UUID.randomUUID().toString());
          ChatProducer producer = new ChatProducer(TOPIC)) {
      Future<?> future = executorService.submit(consumer);
      System.out.print("Connected, press Ctrl+C to exit\n");
      while (!future.isDone()) {
        String message = scanner.nextLine();
        producer.sendMessage(username, message);
      }
    } catch (Exception e) {
        System.out.println("Closing chat...");
    } finally {
        executorService.shutdownNow();
    }
  }
}