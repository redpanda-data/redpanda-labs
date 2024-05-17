""" Uses LangChain's sitemap loader and text splitter to generate documents from redpanda.com.
The documents are sent to a Redpanda topic. """

import os
import json
import argparse
from typing import List
import nest_asyncio
from tqdm import tqdm
from langchain_community.document_loaders.sitemap import SitemapLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_core.documents import Document
from confluent_kafka import Producer
from dotenv import load_dotenv

load_dotenv()


def load_documents(sitemap: str):
    """Load the sitemap and split text into smaller documents."""

    nest_asyncio.apply()
    sitemap = SitemapLoader(web_path=sitemap)
    sitemap.requests_per_second = 4
    pages = sitemap.load()

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=2000, chunk_overlap=200)
    docs = splitter.split_documents(pages)
    print(f"Prepared {len(docs)} documents from the sitemap")
    return docs


def send_to_kafka(docs: List[Document]):
    """Produce docs to Kafka topic."""

    conf = {"bootstrap.servers": os.getenv("REDPANDA_SERVERS")}
    user = os.getenv("REDPANDA_USER")
    password = os.getenv("REDPANDA_PASS")
    if user is not None and password is not None:
        conf["security.protocol"] = "SASL_SSL"
        conf["sasl.mechanism"] = "SCRAM-SHA-256"
        conf["sasl.username"] = user
        conf["sasl.password"] = password

    topics = os.getenv("REDPANDA_TOPICS")
    producer = Producer(conf)
    for d in tqdm(docs, desc="Producing to Kafka", ascii=True):
        v = {"text": d.page_content, "metadata": d.metadata}
        producer.produce(topics, value=json.dumps(v).encode("utf-8"))
    producer.flush()
    print(f"Sent {len(docs)} documents to Redpanda topic: {topics}")


def main():
    """Generate documents and send them to Kafka."""

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-s",
        "--sitemap",
        type=str,
        required=False,
        default="https://www.bbc.com/sport/sitemap.xml",
    )
    args = parser.parse_args()
    docs = load_documents(args.sitemap)
    send_to_kafka(docs)


if __name__ == "__main__":
    main()
