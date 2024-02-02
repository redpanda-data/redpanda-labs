package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	avro "github.com/linkedin/goavro/v2"
	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform"
	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform/sr"
)

var codec avro.Codec

func main() {
	// Register schema:
	//	jq '. | {schema: tojson}' schema.avsc | \
	//		curl -X POST "http://localhost:58646/subjects/nasdaq_history_avro-value/versions" \
	//		-H "Content-Type: application/vnd.schemaregistry.v1+json" \
	//		-d @-
	idStr, set := os.LookupEnv("SCHEMA_ID")
	if !set {
		panic("SCHEMA_ID environment variable not set")
	}
	id, err := strconv.Atoi(idStr)
	if err != nil {
		panic(fmt.Sprintf("SCHEMA_ID not an integer: %s", idStr))
	}
	registry := sr.NewClient()
	schema, err := registry.LookupSchemaById(id)
	if err != nil {
		panic(fmt.Sprintf("Unable to retrieve schema for id: %d", id))
	}
	fmt.Printf("Schema: %s", schema.Schema)

	// Create Avro codec to use in transform function
	c, err := avro.NewCodec(schema.Schema)
	if err != nil {
		panic(fmt.Sprintf("Error creating Avro codec: %v", err))
	}
	codec = *c
	transform.OnRecordWritten(toAvro)
}

func parse(r string) (map[string]any, error) {
	p := strings.Split(r, ",")
	volume, err := strconv.Atoi(p[2])
	if err != nil {
		return nil, err
	}
	m := map[string]any{
		"Date":   p[0],
		"Last":   p[1],
		"Volume": volume,
		"Open":   p[3],
		"High":   p[4],
		"Low":    p[5],
	}
	return m, nil
}

func toAvro(e transform.WriteEvent, w transform.RecordWriter) error {
	m, err := parse(string(e.Record().Value))
	if err != nil {
		fmt.Printf("Unable to parse record value: %v", err)
	}
	binary, err := codec.BinaryFromNative(nil, m)
	if err != nil {
		fmt.Printf("Unable to encode map: %v", err)
	}
	record := transform.Record{
		Key:   e.Record().Key,
		Value: binary,
	}
	return w.Write(record)
}
