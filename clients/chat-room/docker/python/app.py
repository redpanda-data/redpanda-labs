import threading
from producer import ChatProducer
from consumer import ChatConsumer
from admin import ChatAdmin
brokers = ["localhost:19092"]
topic = "chat-room"
def consumer_thread(consumer):
  consumer.print_messages()
if __name__ == "__main__":
  admin = ChatAdmin(brokers)
  if not admin.topic_exists(topic):
    print(f"Creating topic: {topic}")
    admin.create_topic(topic)
  username = input("Enter your username: ")
  producer = ChatProducer(brokers, topic)
  consumer = ChatConsumer(brokers, topic)
  consumer_t = threading.Thread(target=consumer_thread, args=(consumer,))
  consumer_t.daemon = True
  consumer_t.start()
  print("Connected. Press Ctrl+C to exit")
  try:
    while True:
      message = input()
      producer.send_message(username, message)
  except KeyboardInterrupt:
    pass
  finally:
    print("\nClosing chat...")
    producer.close()
    consumer.close()
    admin.close()
    consumer_t.join(1)