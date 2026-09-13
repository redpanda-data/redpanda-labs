package main

import (
	"crypto/tls"
	"os"
	"strings"

	"github.com/twmb/franz-go/pkg/kgo"
	"github.com/twmb/franz-go/pkg/sasl/scram"
)

// tag::config[]
// clientOpts builds the connection options from environment variables.
//
//	REDPANDA_BROKERS         comma-separated bootstrap servers (default localhost:19092)
//	REDPANDA_SASL_USERNAME   SASL/SCRAM user; when set, TLS and SASL are enabled
//	REDPANDA_SASL_PASSWORD   SASL/SCRAM password
//	REDPANDA_SASL_MECHANISM  SCRAM-SHA-256 (default) or SCRAM-SHA-512
func clientOpts() []kgo.Opt {
	brokers := getenv("REDPANDA_BROKERS", "localhost:19092")
	opts := []kgo.Opt{kgo.SeedBrokers(strings.Split(brokers, ",")...)}

	user := os.Getenv("REDPANDA_SASL_USERNAME")
	if user == "" {
		return opts
	}
	auth := scram.Auth{User: user, Pass: os.Getenv("REDPANDA_SASL_PASSWORD")}
	mechanism := auth.AsSha256Mechanism()
	if strings.EqualFold(getenv("REDPANDA_SASL_MECHANISM", "SCRAM-SHA-256"), "SCRAM-SHA-512") {
		mechanism = auth.AsSha512Mechanism()
	}
	return append(opts,
		kgo.DialTLSConfig(new(tls.Config)),
		kgo.SASL(mechanism),
	)
}
// end::config[]

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
