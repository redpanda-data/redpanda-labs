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

# Configure logging to display information and error messages
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

# Initialize Kafka producer with serialization settings for keys and values
producer = KafkaProducer(
    bootstrap_servers=args.brokers.split(','),
    key_serializer=lambda k: k.encode('utf-8') if k else None,
    value_serializer=lambda v: v.encode('utf-8')
)

# Callback function to log message delivery success
def on_send_success(record_metadata):
    logging.info(f"Message delivered to {record_metadata.topic} [{record_metadata.partition}] offset {record_metadata.offset}")
# Callback function to log message delivery success
def on_send_error(excp):
    logging.error('Message delivery failed: %s', excp)

# Initialize Kafka admin client to manage topics
admin_client = KafkaAdminClient(bootstrap_servers=args.brokers.split(','))
topic_list = [NewTopic(name=args.topic, num_partitions=1, replication_factor=1)]
try:
    admin_client.create_topics(new_topics=topic_list, validate_only=False)
except Exception as e:
    logging.error("Failed to create topic: %s", e)

# Main loop to process each CSV file found in the directory
data_files = glob.glob(f"{pathlib.Path(args.file).parent.resolve()}/*.csv")
try:
    while True:
        for file in data_files:
            logging.info("Processing file: %s", file)
            with open(file, newline='', encoding='utf-8') as csvfile:
                reader = csv.DictReader(csvfile)
                rows = list(reader)
                if args.reverse:
                    rows.reverse()  # Reverse the order of data if requested

                for row in rows:
                    if args.date and args.date in row:
                        # Increment date by one second for simulation purposes
                        row[args.date] = (datetime.strptime(row[args.date], "%m/%d/%Y") + timedelta(seconds=1)).strftime("%m/%d/%Y")
                    message = str(row)
                    # Send the message to Redpanda
                    producer.send(args.topic, value=message).add_callback(on_send_success).add_errback(on_send_error)

                producer.flush()  # Ensure all messages are sent before continuing

        if not args.loop:
            break # Exit the loop if not set to continuous mode
except KeyboardInterrupt:
    logging.info("Terminating the producer.")

producer.close() # Close the producer connection gracefully
logging.info("Producer has been closed.")