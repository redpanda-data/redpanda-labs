package main

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"os"
	"strconv"

	avro "github.com/linkedin/goavro/v2"
	redpanda "github.com/redpanda-data/redpanda/src/go/transform-sdk"
	sr "github.com/redpanda-data/redpanda/src/go/transform-sdk/sr"
)

var codec avro.Codec
var schemaId int32

func main() {
	// Get the schema from the Schema registry and setup the Avro codec
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

	// Create Avro codec to use in transform function
	c, err := avro.NewCodec(schema.Schema)
	if err != nil {
		panic(fmt.Sprintf("Error creating Avro codec: %v", err))
	}
	codec = *c
	schemaId = int32(id)

	// Register your transform function.
	redpanda.OnRecordWritten(toAvro)
}

type iss_now struct {
	Message      string `json:"message"`
	Timestamp    int32  `json:"timestamp"`
	Iss_position iss_position
}

type iss_position struct {
	Latitude  float64 `json:"latitude,string"`
	Longitude float64 `json:"longitude,string"`
}

func toAvro(e redpanda.WriteEvent) ([]redpanda.Record, error) {
	// Parse our inbound JSON into a map[string]any
	position, err := parse(e.Record().Value)
	if err != nil {
		fmt.Printf("Unable to parse record value: %v", err)
		return nil, nil
	}

	// Build the magic byte and schema ID (first byte is 0x0 and then 4 bytes for the ID as a BigEndian unsigned int)
	bs := make([]byte, 4)
	binary.BigEndian.PutUint32(bs, uint32(schemaId))
	hdr := append([]byte{0}, bs...)

	// Use GoAvro to encode as binary, appending onto the hdr slice
	binaryOut, err := codec.BinaryFromNative(hdr, position)
	if err != nil {
		fmt.Printf("Unable to encode map: %v", err)
		return nil, nil
	}

	// Create a Record with the existing key and our new binary value
	record := redpanda.Record{
		Key:   e.Record().Key,
		Value: binaryOut,
	}

	// Return a single entry slice with this record in it
	return []redpanda.Record{record}, nil
}

func parse(bytes []byte) (map[string]any, error) {
	// Unmarshal JSON into struct
	iss_pos := iss_now{}
	err := json.Unmarshal(bytes, &iss_pos)
	if err != nil {
		return nil, err
	}

	// Convert struct that's in the upstream format into our flatter format
	outputMap := map[string]any{}
	outputMap["longitude"] = iss_pos.Iss_position.Longitude
	outputMap["latitude"] = iss_pos.Iss_position.Latitude
	outputMap["timestamp"] = iss_pos.Timestamp

	// Return map
	return outputMap, nil
}
