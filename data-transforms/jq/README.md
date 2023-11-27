# Redpanda Wasm Data Transform - JQ Filter

This contains a transform using the popular `jq` command line JSON processor.

See the jq manual for more information on how to write a filter: https://jqlang.github.io/jq/manual/

Environment variables:
- FILTER: The jq expression that will executre against record values (required)

To deploy this to a cluster you'll need to run the following in this directory:
```
./build.sh
rpk transform deploy jq.wasm --name=<name> --var=FILTER='.myfilter' --input-topic=src --output-topic=sink
```
