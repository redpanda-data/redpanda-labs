""" Uses LangChain's sitemap loader and text splitter to generate documents from redpanda.com.
The documents are sent to a Redpanda topic. """

import os
import json
import nest_asyncio
from tqdm import tqdm
from langchain_community.document_loaders.sitemap import SitemapLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter
from confluent_kafka import Producer
from dotenv import load_dotenv

load_dotenv()

nest_asyncio.apply()
sitemap = SitemapLoader(web_path="https://redpanda.com/sitemap.xml")
sitemap.requests_per_second = 4
pages = sitemap.load()

splitter = RecursiveCharacterTextSplitter(chunk_size=2000, chunk_overlap=200)
docs = splitter.split_documents(pages)
print(f"Prepared {len(docs)} documents from the sitemap")

conf = {
    "bootstrap.servers": os.getenv("REDPANDA_SERVERS"),
    "security.protocol": "SASL_SSL",
    "sasl.mechanism": "SCRAM-SHA-256",
    "sasl.username": os.getenv("REDPANDA_USER"),
    "sasl.password": os.getenv("REDPANDA_PASS")
}
topics = os.getenv("REDPANDA_TOPICS")
producer = Producer(conf)
for d in tqdm(docs, desc="Producing to Kafka", ascii=True):
    v = {
        "page_content": d.page_content,
        "metadata": d.metadata
    }
    producer.produce(topics, value=json.dumps(v).encode("utf-8"))
producer.flush()
print(f"Sent {len(docs)} documents to Redpanda topic: {topics}")
