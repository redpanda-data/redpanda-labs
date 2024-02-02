# Redpanda Sarama Example

## Running the example

```shell
go run main.go -h
  -brokers string
    	Comma-separated list of brokers. (default "localhost:9092")
  -group string
    	Consumer group name. (default "test-group")
  -password string
    	SASL password.
  -tls
    	Enable TLS. (default false)
  -topic string
    	Topic to produce to and consume from. (default "test")
  -username string
    	SASL username.
```

## Redpanda Cloud

```
  -brokers
        Copy the "Cluster hosts" string from the Overview page.
  -topic
        Create a new topic on the Topics page.
  -username
        Create a new service account on the Security page and paste the name here (don't forget to copy the password).
        Create the associated ACLs for the topic, service account, and consumer group.
  -password
        Paste the password here.
```