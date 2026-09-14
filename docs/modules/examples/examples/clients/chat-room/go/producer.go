package main

import (
	"context"
	"encoding/json"

	"github.com/twmb/franz-go/pkg/kgo"
)

// tag::producer[]
type Producer struct {
	client *kgo.Client
	topic  string
}

func NewProducer(topic string) *Producer {
	client, err := kgo.NewClient(clientOpts()...)
	if err != nil {
		panic(err)
	}
	return &Producer{client: client, topic: topic}
}

// SendMessage produces one JSON-encoded chat message.
func (p *Producer) SendMessage(user, message string) {
	b, _ := json.Marshal(Message{User: user, Message: message})
	p.client.Produce(context.Background(), &kgo.Record{Topic: p.topic, Value: b}, nil)
}
// end::producer[]

func (p *Producer) Close() {
	p.client.Close()
}
