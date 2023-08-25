# Redpanda Wasm Data Transform - CSV to Avro

This is an example of how to transcode CSV records to Avro records. The data transform reads CSV
formatted records from the input topic, converts them to Avro encoded records based on the given
schema, and writes them to the output topic.

Environment variables:
- `SCHEMA_ID`: The ID of the schema stored in the Redpanda schema registry (required)

## Register schema

```shell
jq '. | {schema: tojson}' schema.avsc | \
   curl -X POST "http://localhost:58646/subjects/nasdaq_history_avro-value/versions" \
        -H "Content-Type: application/vnd.schemaregistry.v1+json" \
        -d @-
```

If the request is successful the version `id` is returned. This is the `id` to use for the data 
transforms `SCHEMA_ID` environment variable. The version `id` can also be retrieved using the 
following command:

```shell
curl -s "http://localhost:58646/subjects/nasdaq_history_avro-value/versions" | jq .
[
  1
]
```

## Deploy data transform

To deploy the data transform to a cluster you'll need to run the following in this directory:

```shell
rpk transform build
rpk transform deploy --env-var=SCHEMA_ID=1 \
                     --input-topic=nasdaq_history_csv \
                     --output-topic=nasdaq_history_avro
```
