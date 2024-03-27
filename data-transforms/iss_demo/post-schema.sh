#!/bin/bash

# Convert Avro schema to JSON and post it using curl
jq '. | {schema: tojson}' iss.avsc | curl -X POST "http://localhost:8081/subjects/iss_position/versions" -H "Content-Type: application/vnd.schemaregistry.v1+json" -d @-