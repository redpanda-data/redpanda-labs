This sample explains how to serialize and deserialize Avro messages with Redpanda Schema Registry. For more information, follow https://redpanda.com/blog/produce-consume-apache-avro-tutorial

## How to setup the code?

### Install Python dependencies
Execute the following commands in a terminal window.

```python
python3 -m venv env
source env/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```
Also, note that we’re using the `confluent-kafka` Python SDK for all the API communications with the Redpanda schema registry. It’s a schema-registry-aware SDK that’s also compatible with the Confluent schema registry. Because of that, confluent-kafka will do a lot of heavy lifting for us under the hood, such as adding padding for each message consisting of the magic byte and the schemaID. Also, it can automatically register the schemas with the registry.

Another advantage is that you use the Redpanda schema registry with your Confluent SDK clients, without needing any code changes.

### Start a Redpanda cluster
Locate the `docker-compose.yml` file at the root level of the cloned repository and run the following command in a terminal.

```bash
docker compose up -d
```

That will spin up a single-node Redpanda cluster with the Redpanda console. This Redpanda node contains the schema registry built-in. You can visually explore the schema definitions stored in the schema registry with the Redpanda console.

Access the console by logging into http://localhost:8080/brokers. Click on the Schema Registry in the sidebar to see the schema definitions.

### Run the Python producer
Run the `producer.py` to produce a stream of Avro messages to Redpanda.

```python
python producer.py
```

Log into the Redpanda Console’s Topics page to see if the `clickstream` topic has been populated with a single event.

### Run the Python consumer
Run the `consumer.py` to consume Avro messages from the `clickstream` topic and print message content to the console.

```python
python consumer.py
```
You should see a single event in return, with their deserialized content as follows.

```
Key is :"39950858-1cfd-4d56-a3ac-2bde1c806f6f"
Value is :{"user_id": 2, "event_type": "CLICK", "ts": "2021-12-12"}
```


