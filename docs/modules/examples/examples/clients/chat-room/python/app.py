import threading

from admin import ChatAdmin
from config import TOPIC
from consumer import ChatConsumer
from producer import ChatProducer


# tag::main[]
def consumer_thread(consumer):
    consumer.print_messages()


if __name__ == "__main__":
    admin = ChatAdmin()
    if not admin.topic_exists(TOPIC):
        print(f"Creating topic: {TOPIC}")
        admin.create_topic(TOPIC)

    username = input("Enter your username: ")
    producer = ChatProducer(TOPIC)
    consumer = ChatConsumer(TOPIC)

    consumer_t = threading.Thread(target=consumer_thread, args=(consumer,), daemon=True)
    consumer_t.start()
    print("Connected. Press Ctrl+C to exit")
    try:
        while True:
            message = input()
            if message.strip():
                producer.send_message(username, message)
    except (KeyboardInterrupt, EOFError):
        pass
    finally:
        print("\nClosing chat...")
        producer.close()
        consumer.close()
        admin.close()
        consumer_t.join(1)
# end::main[]
