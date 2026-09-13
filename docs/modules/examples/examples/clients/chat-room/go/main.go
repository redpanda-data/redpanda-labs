package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// tag::main[]
type Message struct {
	User    string `json:"user"`
	Message string `json:"message"`
}

func main() {
	topic := getenv("REDPANDA_TOPIC", "chat-room")

	admin := NewAdmin()
	if !admin.TopicExists(topic) {
		admin.CreateTopic(topic)
	}
	admin.Close()

	fmt.Print("Enter user name: ")
	reader := bufio.NewReader(os.Stdin)
	username, _ := reader.ReadString('\n')
	username = strings.TrimSpace(username)

	producer := NewProducer(topic)
	defer producer.Close()
	consumer := NewConsumer(topic)
	defer consumer.Close()

	go consumer.PrintMessages()
	fmt.Println("Connected. Press Ctrl+C to exit")
	for {
		message, err := reader.ReadString('\n')
		if err != nil {
			return
		}
		if message = strings.TrimSpace(message); message != "" {
			producer.SendMessage(username, message)
		}
	}
}
// end::main[]
