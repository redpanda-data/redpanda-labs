package main

import (
	_ "embed"
	"encoding/json"
	"log"

	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform"
	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform/sr"
)

// JSON Schema definitions embedded from schema files
//
//go:embed schemas/orders.json
var ordersSchema string

//go:embed schemas/inventory.json
var inventorySchema string

//go:embed schemas/customers.json
var customersSchema string

// Valid output topics for routing
var validTopics = map[string]bool{
	"orders":    true,
	"inventory": true,
	"customers": true,
}

type BatchMessage struct {
	Updates []TableUpdate `json:"updates"`
}

type TableUpdate struct {
	Table string          `json:"table"`
	Data  json.RawMessage `json:"data"`
}

func main() {
	// Initialize Schema Registry client and register schemas dynamically
	client := sr.NewClient()

	schemas := map[string]string{
		"orders":    ordersSchema,
		"inventory": inventorySchema,
		"customers": customersSchema,
	}

	log.Printf("Registering schemas in Schema Registry...")
	for topic, schemaDef := range schemas {
		subject := topic + "-value" // Follow {topic-name}-value naming convention

		schema := sr.Schema{
			Schema: schemaDef,
			Type:   sr.TypeJSON,
		}

		registered, err := client.CreateSchema(subject, schema)
		if err != nil {
			log.Printf("Warning: Failed to register schema for %s: %v", topic, err)
			log.Printf("Continuing anyway - schema may already be registered")
		} else {
			log.Printf("Registered schema for %s: ID=%d", topic, registered.ID)
		}
	}

	log.Printf("Starting multi-topic fanout transform")
	transform.OnRecordWritten(fanoutBatch)
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

		// Create output record with plain JSON data for Iceberg compatibility
		// Note: We write plain JSON (not Schema Registry wire format) because
		// topics are configured with value_schema_latest mode, which means
		// Redpanda handles schema validation automatically at the broker level.
		outRecord := transform.Record{
			Key:   record.Key,
			Value: update.Data, // Individual update data as plain JSON
		}

		// Write to the target topic
		if err := writer.Write(outRecord, transform.ToTopic(update.Table)); err != nil {
			log.Printf("  [%d] Failed to route to %s: %v", i, update.Table, err)
			return err
		}

		log.Printf("  [%d] Routed update to %s", i, update.Table)
	}

	log.Printf("Successfully fanned out %d updates", len(batch.Updates))
	return nil
}
