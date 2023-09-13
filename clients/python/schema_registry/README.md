# Redpanda Python Examples

## Using the schema registry

The `redpanda_schema_example.py` script demonstrates how to do two things:

1. Store and retrieve an Avro schema using Redpanda's native schema registry, and 
2. Use that schema to produce and consume Avro messages in Redpanda using the `kafka-python` library

For more information on the schema registry please read Ben Pope's excellent blog post: [Schema Registry - The event is the API](https://vectorized.io/blog/schema_registry/).

## Data

The data used in this example is historic weather station recordings provided by the [UK's Met Office](https://www.metoffice.gov.uk/research/climate/maps-and-data/historic-station-data) under their open data policy. The data is provided in plain text and includes monthly aggregations for:

* Mean daily maximum temperature (tmax)
* Mean daily minimum temperature (tmin)
* Days of air frost (af)
* Total rainfall (rain)
* Total sunshine duration (sun)

See [weather.avsc](data/weather.avsc) for the corresponding Avro schema.

## Setup

You can run this example against any Redpanda cluster, but the easiest way to get started is to stand up a cluster on your local machine using Docker and `rpk container start`. See [Starting a local cluster](https://vectorized.io/docs/guide-rpk-container/) for further instructions. If you prefer to use Docker directly then check out the [Docker Quick Start Guide](https://vectorized.io/docs/quick-start-docker/).

You need two pieces of information about your cluster to run the example:

1. A list of broker addresses. `rpk container start` will give you this:
```shell
% rpk container start
Starting cluster
Waiting for the cluster to be ready...
  NODE ID  ADDRESS
  0        127.0.0.1:49648

Cluster started! You may use rpk to interact with it. E.g:

rpk cluster info --brokers 127.0.0.1:49648
```
2. The schema registry URI. This is typically `http://localhost:8081` but `rpk container start` will map it to a different port in Docker:
```shell
% docker container ls
...PORTS
...0.0.0.0:49650->8081/tcp
```

### Create Python virtual environment

```shell
% python3 -m venv env
% source env/bin/activate
% pip install -r requirements.txt
```

## Running the example

```shell
% python3 redpanda_schema_example.py -h
usage: redpanda_schema_example.py [-h] [-t TOPIC] brokers registry

positional arguments:
  brokers               List of Redpanda brokers
  registry              Redpanda schema registry URI

options:
  -h, --help            show this help message and exit
  -t TOPIC, --topic TOPIC
                        Name of topic
```

Using the example addresses from above, running `python3 redpanda_schema_example.py 127.0.0.1:49648 http://127.0.0.1:49650` will do the following:

1. Post the Avro schema [weather.avsc](data/weather.avsc) to the Redpanda schema registry
2. Read the data file [hurndata.txt](data/hurndata.txt) and send the messages to Redpanda. The producer is configured to serialize the messages into Avro using `value_serializer`
3. Retrieve the Avro schema from the Redpanda schema registry
4. Consume the messages from Redpanda and deserialize them into JSON using the Avro schema in `value_deserializer`

You can view the Avro formatted messages in Redpanda using `rpk`:

```shell
% rpk topic consume station-data --brokers 127.0.0.1:49648
...
{
 "message": "\u00082021\u00029\u000821.6\u000810.4\u00020\u000841.6\u000c138.4#",
 "partition": 0,
 "offset": 1553,
 "size": 31,
 "timestamp": "2021-10-22T11:14:46.145+01:00"
}
```
