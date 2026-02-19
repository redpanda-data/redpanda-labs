package main

import (
	"log"

	"github.com/redpanda-data/redpanda/src/transform-sdk/go/transform"
)

// Valid output topics for routing
var validTopics = map[string]bool{
	"orders":    true,
	"inventory": true,
	"customers": true,
}

func main() {
	log.Printf("Starting multi-topic fanout transform")
	transform.OnRecordWritten(routeMessage)
}

// routeMessage reads the target_table header and routes the message
// to the appropriate output topic. Messages contain plain JSON that
// will be validated by Redpanda against the latest schema in Schema Registry.
func routeMessage(event transform.WriteEvent, writer transform.RecordWriter) error {
	// Read the target_table header to determine routing
	targetTable := ""
	for _, header := range event.Record().Headers {
		if string(header.Key) == "target_table" {
			targetTable = string(header.Value)
			break
		}
	}

	if targetTable == "" {
		log.Printf("No target_table header found, skipping message")
		return nil
	}

	if !validTopics[targetTable] {
		log.Printf("Invalid target table: %s", targetTable)
		return nil
	}

	// Route the message to the target topic
	// Message value contains plain JSON that Redpanda will validate
	// against the latest schema from Schema Registry (value_schema_latest mode)
	record := transform.Record{
		Key:     event.Record().Key,
		Value:   event.Record().Value,
		Headers: event.Record().Headers,
	}

	if err := writer.Write(record, transform.ToTopic(targetTable)); err != nil {
		log.Printf("Failed to route message to %s: %v", targetTable, err)
		return err
	}

	log.Printf("Routed message to topic: %s", targetTable)
	return nil
}
