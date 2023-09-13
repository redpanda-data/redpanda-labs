package main

import (
	"context"
	"crypto/sha256"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/xdg-go/scram"

	"github.com/Shopify/sarama"
)

type Consumer struct{}

func (consumer *Consumer) Setup(session sarama.ConsumerGroupSession) error {
	log.Println(session.Claims())
	return nil
}

func (consumer *Consumer) Cleanup(_ sarama.ConsumerGroupSession) error {
	return nil
}

func (consumer *Consumer) ConsumeClaim(session sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	for msg := range claim.Messages() {
		log.Printf("Consumed message from partition %d at offset %d: %s", msg.Partition, msg.Offset, msg.Value)
		session.MarkMessage(msg, "")
	}
	return nil
}

type SCRAMClient struct {
	*scram.Client
	*scram.ClientConversation
	scram.HashGeneratorFcn
}

func (x *SCRAMClient) Begin(username, password, authzID string) (err error) {
	x.Client, err = x.HashGeneratorFcn.NewClient(username, password, authzID)
	if err != nil {
		return err
	}
	x.ClientConversation = x.Client.NewConversation()
	return nil
}

func (x *SCRAMClient) Step(challenge string) (response string, err error) {
	response, err = x.ClientConversation.Step(challenge)
	return
}

func (x *SCRAMClient) Done() bool {
	return x.ClientConversation.Done()
}

func main() {
	topic := flag.String("topic", "test", "Topic to produce to and consume from.")
	groupName := flag.String("group", "test-group", "Consumer group name.")
	brokers := flag.String("brokers", "localhost:9092", "Comma-separated list of brokers.")
	username := flag.String("username", "", "SASL username.")
	password := flag.String("password", "", "SASL password.")
	useTLS := flag.Bool("tls", false, "Enable TLS.")
	flag.Parse()

	conf := sarama.NewConfig()
	conf.Producer.Return.Successes = true
	conf.Consumer.Offsets.Initial = sarama.OffsetOldest
	conf.Consumer.Group.Session.Timeout = time.Duration(60 * time.Second)
	if *username != "" && *password != "" {
		conf.Net.SASL.Enable = true
		conf.Net.SASL.User = *username
		conf.Net.SASL.Password = *password
		conf.Net.SASL.Handshake = true
		conf.Net.SASL.SCRAMClientGeneratorFunc = func() sarama.SCRAMClient { return &SCRAMClient{HashGeneratorFcn: sha256.New} }
		conf.Net.SASL.Mechanism = sarama.SASLTypeSCRAMSHA256
	}
	conf.Net.TLS.Enable = *useTLS

	sarama.Logger = log.New(os.Stderr, "[Sarama] ", log.LstdFlags)
	client, err := sarama.NewClient(strings.Split(*brokers, ","), conf)
	if err != nil {
		log.Fatalln(err)
	}
	defer func() {
		if err := client.Close(); err != nil {
			log.Fatalln(err)
		}
	}()

	// Produce messages synchronously
	producer, err := sarama.NewSyncProducerFromClient(client)
	if err != nil {
		log.Fatalln(err)
	}

	for i := 1; i < 10; i++ {
		msg := &sarama.ProducerMessage{
			Topic: *topic,
			Value: sarama.StringEncoder(fmt.Sprintf("Message #%d", i)),
		}
		partition, offset, err := producer.SendMessage(msg)
		if err != nil {
			log.Printf("Failed to send message: %s", err.Error())
		} else {
			log.Printf("Message sent to partition %d at offset %d: %s", partition, offset, msg.Value)
		}
	}
	producer.Close()

	// Consume messages
	group, err := sarama.NewConsumerGroupFromClient(*groupName, client)
	if err != nil {
		log.Fatalln(err)
	}

	ctx := context.Background()
	for {
		err := group.Consume(ctx, []string{*topic}, &Consumer{})
		if err != nil {
			log.Fatalln(err)
		}
	}
}
