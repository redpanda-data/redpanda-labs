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

		// Optional: Validate it's valid JSON
		var batch BatchMessage
		if err := json.Unmarshal([]byte(line), &batch); err != nil {
			log.Printf("Failed to parse batch: %v", err)
			continue
		}

		batchCount++
		fmt.Printf("📦 Batch %d (contains %d updates)\n", batchCount, len(batch.Updates))

		// Send the ENTIRE batch as a single message
		record := &kgo.Record{
			Topic: "events",
			Value: []byte(line), // Raw JSON batch
			// No headers - transform will parse
		}

		if err := client.ProduceSync(ctx, record).FirstErr(); err != nil {
			log.Printf("  ✗ Failed to produce batch: %v", err)
		} else {
			messageCount++
			fmt.Printf("  ✓ Sent batch to events topic\n")
		}
		fmt.Println()
	}

	if err := scanner.Err(); err != nil {
		log.Fatalf("Error reading stdin: %v", err)
	}

	fmt.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	fmt.Printf("✓ Produced %d batches\n", messageCount)
	fmt.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
}
