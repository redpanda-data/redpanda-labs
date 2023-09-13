# Redpanda franz-go example

How to create a topic, write to, and read from a Redpanda cluster using the [franz-go](https://github.com/twmb/franz-go) Kafka API client. This example has been tested on local Redpanda clusters that were spun up using [docker-compose](../../../docker-compose/), as well as Redpanda FMC/BYOC cluster with TLS and SASL SCRAM enabled (you just need to download the TLS certs and create the necessary users and ACLs).

```shell
go build -o redpanda-franz-example

./redpanda-franz-example -h
Usage of ./redpanda-franz-example:
  -brokers string
    	Comma-separated list of brokers. (default "localhost:9092")
  -ca string
    	Path to PEM-formatted CA file.
  -clientCert string
    	Path to PEM-formatted cert file.
  -clientKey string
    	Path to PEM-formatted key file.
  -group string
    	Consumer group name. (default "test-group")
  -password string
    	SASL password.
  -saslMechanism string
    	'plain', 'SCRAM-SHA-256', or 'SCRAM-SHA-512'
  -tls
    	Enable TLS.
  -topic string
    	Topic to produce to and consume from. (default "test")
  -username string
    	SASL username.
```