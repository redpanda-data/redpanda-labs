# Redpanda Wasm Data Transform - CSV to Avro

This is an example of how to transcode CSV records to Avro records. The data transform reads CSV
formatted records from the input topic, converts them to Avro encoded records based on the given
schema, and writes them to the output topic.

Environment variables:
- `SCHEMA_ID`: The ID of the schema stored in the Redpanda schema registry (required)

# Test

## Start container

Make sure you're using the technical preview of `rpk` that supports the data transforms 
architecture.

```shell
./rpk container start
export RPK_BROKERS="127.0.0.1:53360"
export RPK_ADMIN_HOSTS="127.0.0.1:53364"
./rpk cluster info
./rpk cluster health
```

## Create topics

```shell
./rpk topic create nasdaq_history_csv
./rpk topic create nasdaq_history_avro
```

## Register schema

```shell
# find schema registry port
docker container ls

...PORTS
...0.0.0.0:53362->8081/tcp...

# create _schemas topic
curl -s "http://localhost:53362/schemas/types" | jq .

# post schema
jq '. | {schema: tojson}' schema.avsc | \
   curl -X POST "http://localhost:53362/subjects/nasdaq_history_avro-value/versions" \
        -H "Content-Type: application/vnd.schemaregistry.v1+json" \
        -d @-
```

If the request is successful the version `id` is returned. This is the `id` to use for the data 
transforms `SCHEMA_ID` environment variable. The version `id` can also be retrieved using the 
following command:

```shell
curl -s "http://localhost:53362/subjects/nasdaq_history_avro-value/versions" | jq .
[
  1
]
```

## Deploy data transform

To deploy the data transform to a cluster you'll need to run the following in this directory:

```shell
./rpk transform build
./rpk transform deploy --env-var=SCHEMA_ID=1 \
                       --input-topic=nasdaq_history_csv \
                       --output-topic=nasdaq_history_avro
```

## Produce CSV data

```shell
cd test
./produce.sh HistoricalData_1692981579371.csv nasdaq_history_csv
```

## Consume CSV data

```shell
./rpk topic consume nasdaq_history_csv
```

## Consume Avro data

```shell
./rpk topic consume nasdaq_history_avro
```
