""" Uses LangChain's sitemap loader and text splitter to generate documents from redpanda.com.
The documents are sent to a Redpanda topic. """

import os
import json
import argparse
from typing import List
import nest_asyncio
from tqdm import tqdm
from langchain_community.document_loaders.sitemap import SitemapLoader
from langchain_community.document_loaders import WebBaseLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_core.documents import Document
from confluent_kafka import Producer
from dotenv import load_dotenv

load_dotenv()


def load_document(url: str):
    """Loads webpage and splits text into smaller documents."""

    loader = WebBaseLoader(url)
    loader.requests_kwargs = {"verify": False}
    page = loader.load()
    return _split(page)


def load_sitemap(sitemap: str):
    """Loads the sitemap and splits text into smaller documents."""

    nest_asyncio.apply()
    sitemap = SitemapLoader(web_path=sitemap)
    sitemap.requests_per_second = 4
    pages = sitemap.load()
    return _split(pages)


def _split(docs: List[Document]) -> List[Document]:
    """Splits the documents into smaller chunks of text."""

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=2000, chunk_overlap=200)
    chunks = splitter.split_documents(docs)
    print(f"Prepared {len(chunks)} documents")
    return chunks


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
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("-s", "--sitemap", type=str)
    group.add_argument("-u", "--url", type=str)
    args = parser.parse_args()

    if args.sitemap is not None:
        docs = load_sitemap(args.sitemap)
    elif args.url is not None:
        docs = load_document(args.url)
    send_to_kafka(docs)


if __name__ == "__main__":
    main()
