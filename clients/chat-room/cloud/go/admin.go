package main
import (
    "context"
    "fmt"
    "crypto/tls"
    "github.com/twmb/franz-go/pkg/kadm"
    "github.com/twmb/franz-go/pkg/kgo"
    "github.com/twmb/franz-go/pkg/sasl/scram"
)
type Admin struct {
    client *kadm.Client
}
func NewAdmin(brokers []string) *Admin {
    client, err := kgo.NewClient(
        kgo.SeedBrokers(brokers...),
        kgo.DialTLSConfig(new(tls.Config)),
        kgo.SASL(scram.Auth{User: "redpanda-chat-account",Pass: "<password>",
        }.AsSha256Mechanism()),
    )
    if err != nil {
        panic(err)
    }
    admin := kadm.NewClient(client)
    return &Admin{client: admin}
}
func (a *Admin) TopicExists(topic string) bool {
    ctx := context.Background()
    topicsMetadata, err := a.client.ListTopics(ctx)
    if err != nil {
        panic(err)
    }
    for _, metadata := range topicsMetadata {
        if metadata.Topic == topic {
            return true
        }
    }
    return false
}
func (a *Admin) CreateTopic(topic string) {
    ctx := context.Background()
    resp, err := a.client.CreateTopics(ctx, 1, 1, nil, topic)
    if err != nil {
        panic(err)
    }
    for _, ctr := range resp {
        if ctr.Err != nil {
            fmt.Printf("Unable to create topic '%s': %s", ctr.Topic, ctr.Err)
        } else {
            fmt.Printf("Created topic '%s'\n", ctr.Topic)
        }
    }
}
func (a *Admin) Close() {
    a.client.Close()
}