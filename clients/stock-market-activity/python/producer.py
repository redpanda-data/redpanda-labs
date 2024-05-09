import os
import csv
import glob
import logging
import pathlib
import sys
import argparse
from datetime import datetime, timedelta
from kafka import KafkaProducer
from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import KafkaError

logging.basicConfig(level=logging.INFO)

# Parse command-line arguments
parser = argparse.ArgumentParser(description="Streams CSV data into a Kafka topic using kafka-python-ng.")
parser.add_argument("-f", "--file", default="../data/market_activity.csv", help="Path to the CSV file.")
parser.add_argument("-t", "--topic", default="market_activity", help="Kafka topic to publish the messages.")
parser.add_argument("-b", "--brokers", default="localhost:9092", help="Comma-separated list of brokers.")
parser.add_argument("-d", "--date", help="Date column to manipulate.")
parser.add_argument("-r", "--reverse", action="store_true", help="Reverse the order of data before sending.")
parser.add_argument("-l", "--loop", action="store_true", help="Loop through data continuously.")
args = parser.parse_args()

# Configure Kafka producer
producer = KafkaProducer(
    bootstrap_servers=args.brokers.split(','),
    key_serializer=lambda k: k.encode('utf-8') if k else None,
    value_serializer=lambda v: v.encode('utf-8')
)

# Function to log message delivery status
def on_send_success(record_metadata):
    logging.info(f"Message delivered to {record_metadata.topic} [{record_metadata.partition}] offset {record_metadata.offset}")

def on_send_error(excp):
    logging.error('Message delivery failed: %s', excp)

# Kafka admin client for topic creation
admin_client = KafkaAdminClient(bootstrap_servers=args.brokers.split(','))
topic_list = [NewTopic(name=args.topic, num_partitions=1, replication_factor=1)]
try:
    admin_client.create_topics(new_topics=topic_list, validate_only=False)
except Exception as e:
    logging.error("Failed to create topic: %s", e)

# Main logic for processing files and sending data
data_files = glob.glob(f"{pathlib.Path(args.file).parent.resolve()}/*.csv")

try:
    while True:
        for file in data_files:
            logging.info("Processing file: %s", file)
            with open(file, newline='', encoding='utf-8') as csvfile:
                reader = csv.DictReader(csvfile)
                rows = list(reader)
                if args.reverse:
                    rows.reverse()

                for row in rows:
                    if args.date and args.date in row:
                        row[args.date] = (datetime.strptime(row[args.date], "%m/%d/%Y") + timedelta(seconds=1)).strftime("%m/%d/%Y")
                    message = str(row)
                    # Sending the message
                    producer.send(args.topic, value=message).add_callback(on_send_success).add_errback(on_send_error)

                producer.flush()  # Ensure all messages are sent

        if not args.loop:
            break
except KeyboardInterrupt:
    logging.info("Terminating the producer.")

producer.close()
logging.info("Producer has been closed.")