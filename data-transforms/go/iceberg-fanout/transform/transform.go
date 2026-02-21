package main

import (
	"encoding/json"
	"log"

	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform"
)

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

		// Create output record with just the data portion
		outRecord := transform.Record{
			Key:   record.Key,
			Value: update.Data, // Individual update data, not batch wrapper
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
