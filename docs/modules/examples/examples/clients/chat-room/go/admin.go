package main

import (
	"context"
	"fmt"

	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"
)

// tag::admin[]
type Admin struct {
	client *kadm.Client
}

func NewAdmin() *Admin {
	client, err := kgo.NewClient(clientOpts()...)
	if err != nil {
		panic(err)
	}
	return &Admin{client: kadm.NewClient(client)}
}

// TopicExists returns true when the topic is already in the cluster.
func (a *Admin) TopicExists(topic string) bool {
	topics, err := a.client.ListTopics(context.Background())
	if err != nil {
		panic(err)
	}
	return topics.Has(topic)
}

// CreateTopic creates the topic with one partition and one replica.
func (a *Admin) CreateTopic(topic string) {
	resp, err := a.client.CreateTopics(context.Background(), 1, 1, nil, topic)
	if err != nil {
		panic(err)
	}
	for _, ctr := range resp {
		if ctr.Err != nil {
			fmt.Printf("Unable to create topic '%s': %s\n", ctr.Topic, ctr.Err)
		} else {
			fmt.Printf("Created topic '%s'\n", ctr.Topic)
		}
	}
}
// end::admin[]

func (a *Admin) Close() {
	a.client.Close()
}
