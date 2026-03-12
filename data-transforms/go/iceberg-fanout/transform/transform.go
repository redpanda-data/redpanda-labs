package main

import (
	"encoding/binary"
	"encoding/json"
	_ "embed"
	"fmt"
	"log"

	avro "github.com/linkedin/goavro/v2"
	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform"
	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform/sr"
)

// Avro schema definitions embedded from schema files
//
//go:embed orders.avsc
var ordersAvsc string

//go:embed inventory.avsc
var inventoryAvsc string

//go:embed customers.avsc
var customersAvsc string

// Valid output topics for routing
var validTopics = map[string]bool{
	"orders":    true,
	"inventory": true,
	"customers": true,
}

// Schema IDs and codecs are populated during initialization
var schemaIDs = map[string]int{}
var codecs = map[string]*avro.Codec{}

type BatchMessage struct {
	Updates []TableUpdate `json:"updates"`
}

type TableUpdate struct {
	Table string          `json:"table"`
	Data  json.RawMessage `json:"data"`
}

func main() {
	// Initialize Schema Registry client and register Avro schemas dynamically
	if err := registerSchemas(); err != nil {
		log.Fatalf("Failed to register schemas: %v", err)
	}

	log.Printf("Schema registration complete. Starting multi-topic fanout transform")
	transform.OnRecordWritten(fanoutBatch)
}

// registerSchemas dynamically registers Avro schemas with Schema Registry
func registerSchemas() error {
	client := sr.NewClient()

	schemas := map[string]string{
		"orders":    ordersAvsc,
		"inventory": inventoryAvsc,
		"customers": customersAvsc,
	}

	log.Printf("Registering Avro schemas in Schema Registry...")
	for table, schemaContent := range schemas {
		subject := table + "-value"

		// Register schema
		schema := sr.Schema{
			Schema: schemaContent,
			Type:   sr.TypeAvro,
		}

		registered, err := client.CreateSchema(subject, schema)
		if err != nil {
			return fmt.Errorf("failed to register schema for %s: %w", table, err)
		}

		schemaIDs[table] = registered.ID
		log.Printf("Registered Avro schema for %s: ID=%d", table, registered.ID)

		// Create Avro codec for this schema
		codec, err := avro.NewCodec(schemaContent)
		if err != nil {
			return fmt.Errorf("failed to create Avro codec for %s: %w", table, err)
		}
		codecs[table] = codec
	}

	return nil
}

func fanoutBatch(event transform.WriteEvent, writer transform.RecordWriter) error {
	record := event.Record()

	// Parse the batch JSON
	var batch BatchMessage
	if err := json.Unmarshal(record.Value, &batch); err != nil {
		log.Printf("Failed to parse batch JSON: %v", err)
		return err
	}

	log.Printf("Processing batch with %d updates", len(batch.Updates))

	// Fan out each update to its target topic
	for i, update := range batch.Updates {
		// Validate the target topic
		if !validTopics[update.Table] {
			log.Printf("  [%d] Skipping invalid target table: %s", i, update.Table)
			continue
		}

		// Get schema ID and codec for this table
		schemaID, ok := schemaIDs[update.Table]
		if !ok {
			log.Printf("  [%d] No schema ID for table: %s", i, update.Table)
			continue
		}

		codec, ok := codecs[update.Table]
		if !ok {
			log.Printf("  [%d] No codec for table: %s", i, update.Table)
			continue
		}

		// Parse JSON data into map
		var dataMap map[string]interface{}
		if err := json.Unmarshal(update.Data, &dataMap); err != nil {
			log.Printf("  [%d] Failed to parse data JSON: %v", i, err)
			return err
		}

		// Create Schema Registry wire format header: [magic byte (0x00)][schema_id (4 bytes BE)]
		hdr := make([]byte, 5)
		hdr[0] = 0x00 // Magic byte
		binary.BigEndian.PutUint32(hdr[1:5], uint32(schemaID))

		// Encode as Avro binary, appending to the header
		binaryOut, err := codec.BinaryFromNative(hdr, dataMap)
		if err != nil {
			log.Printf("  [%d] Failed to encode as Avro: %v", i, err)
			return err
		}

		// Create output record with wire format
		outRecord := transform.Record{
			Key:   record.Key,
			Value: binaryOut,
		}

		// Write to the target topic
		if err := writer.Write(outRecord, transform.ToTopic(update.Table)); err != nil {
			log.Printf("  [%d] Failed to route to %s: %v", i, update.Table, err)
			return err
		}

		log.Printf("  [%d] Routed to %s (schema ID: %d, wire format: %d bytes)", i, update.Table, schemaID, len(binaryOut))
	}

	log.Printf("Successfully fanned out %d updates with Avro encoding", len(batch.Updates))
	return nil
}
