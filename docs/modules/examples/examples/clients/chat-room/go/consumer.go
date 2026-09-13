package main

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"github.com/twmb/franz-go/pkg/kgo"
)

// tag::consumer[]
type Consumer struct {
	client *kgo.Client
	topic  string
}

// NewConsumer joins a new consumer group each run, starting from the
// beginning of the topic, so every client sees the whole chat history.
func NewConsumer(topic string) *Consumer {
	opts := append(clientOpts(),
		kgo.ConsumerGroup(uuid.New().String()),
		kgo.ConsumeTopics(topic),
		kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()),
	)
	client, err := kgo.NewClient(opts...)
	if err != nil {
		panic(err)
	}
	return &Consumer{client: client, topic: topic}
}

// PrintMessages polls for records and prints each decoded message.
func (c *Consumer) PrintMessages() {
	for {
		fetches := c.client.PollFetches(context.Background())
		iter := fetches.RecordIter()
		for !iter.Done() {
			record := iter.Next()
			var msg Message
			if err := json.Unmarshal(record.Value, &msg); err != nil {
				fmt.Printf("Error decoding message: %v\n", err)
				continue
			}
			fmt.Printf("%s: %s\n", msg.User, msg.Message)
		}
	}
}
// end::consumer[]

func (c *Consumer) Close() {
	c.client.Close()
}
