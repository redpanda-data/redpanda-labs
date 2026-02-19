package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/twmb/franz-go/pkg/kgo"
)

type BatchMessage struct {
	Updates []TableUpdate `json:"updates"`
}

type TableUpdate struct {
	Table string          `json:"table"`
	Data  json.RawMessage `json:"data"`
}

func main() {
	// Create Kafka client (franz-go)
	client, err := kgo.NewClient(
		kgo.SeedBrokers("localhost:19092"),
	)
	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	ctx := context.Background()
	scanner := bufio.NewScanner(os.Stdin)
	batchCount := 0
	messageCount := 0

	log.Println("Reading JSON batches from stdin...")

	// Read batches from stdin
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}

		var batch BatchMessage
		if err := json.Unmarshal([]byte(line), &batch); err != nil {
			log.Printf("Failed to parse batch: %v", err)
			continue
		}

		batchCount++
		fmt.Printf("📦 Batch %d\n", batchCount)

		// Send each update to events topic
		for _, update := range batch.Updates {
			// Create record with plain JSON value
			// Add header for transform routing
			record := &kgo.Record{
				Topic: "events",
				Value: update.Data, // Plain JSON - no encoding!
				Headers: []kgo.RecordHeader{
					{Key: "target_table", Value: []byte(update.Table)},
				},
			}

			// Produce synchronously (for simplicity in demo)
			if err := client.ProduceSync(ctx, record).FirstErr(); err != nil {
				log.Printf("  ✗ Failed to produce %s: %v", update.Table, err)
			} else {
				messageCount++
				fmt.Printf("  ✓ %s\n", update.Table)
			}
		}
		fmt.Println()
	}

	if err := scanner.Err(); err != nil {
		log.Fatalf("Error reading stdin: %v", err)
	}

	fmt.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	fmt.Printf("✓ Produced %d messages from %d batches\n", messageCount, batchCount)
	fmt.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
}
