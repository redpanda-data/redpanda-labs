// Package conn builds the Kafka and Schema Registry clients from the
// REDPANDA_* variables in .env.
//
// The defaults point at the local broker in docker-compose.yml, so the local
// path needs none of them. Point REDPANDA_BROKERS at a remote cluster, set
// REDPANDA_TLS_ENABLED and the SASL variables, and every service, the rpk
// helper, and the Redpanda Connect pipeline connect there instead. Nothing
// in the services knows which case it is in.
package conn

import (
	"crypto/tls"
	"fmt"
	"strings"

	"github.com/twmb/franz-go/pkg/kgo"
	"github.com/twmb/franz-go/pkg/sasl/scram"
	"github.com/twmb/franz-go/pkg/sr"

	"multiplayer-gaming/services/internal/envvar"
)

// tag::config[]
// Config is the connection half of .env.
type Config struct {
	Brokers            []string // REDPANDA_BROKERS, default redpanda:9092
	TLS                bool     // REDPANDA_TLS_ENABLED
	SASLMechanism      string   // REDPANDA_SASL_MECHANISM: SCRAM-SHA-256 or SCRAM-SHA-512; empty for none
	SASLUsername       string   // REDPANDA_SASL_USERNAME
	SASLPassword       string   // REDPANDA_SASL_PASSWORD
	SchemaRegistryURL  string   // REDPANDA_SCHEMA_REGISTRY_URL, default http://redpanda:8081
	SchemaRegistryUser string   // REDPANDA_SCHEMA_REGISTRY_USERNAME, defaults to the SASL username
	SchemaRegistryPass string   // REDPANDA_SCHEMA_REGISTRY_PASSWORD, defaults to the SASL password
}

// FromEnv reads the variables; unset ones take the local defaults.
func FromEnv() Config {
	c := Config{
		Brokers:           envvar.List("REDPANDA_BROKERS", "redpanda:9092"),
		TLS:               envvar.Bool("REDPANDA_TLS_ENABLED", false),
		SASLMechanism:     strings.ToUpper(envvar.String("REDPANDA_SASL_MECHANISM", "")),
		SASLUsername:      envvar.String("REDPANDA_SASL_USERNAME", ""),
		SASLPassword:      envvar.String("REDPANDA_SASL_PASSWORD", ""),
		SchemaRegistryURL: envvar.String("REDPANDA_SCHEMA_REGISTRY_URL", "http://redpanda:8081"),
	}
	c.SchemaRegistryUser = envvar.String("REDPANDA_SCHEMA_REGISTRY_USERNAME", c.SASLUsername)
	c.SchemaRegistryPass = envvar.String("REDPANDA_SCHEMA_REGISTRY_PASSWORD", c.SASLPassword)
	return c
}

// end::config[]

// tag::clients[]
// KafkaOpts returns the franz-go options for this cluster: seed brokers, TLS
// when enabled, and SASL/SCRAM when a mechanism is set. Append the options
// specific to one client (consumer group, producer settings) after them.
func (c Config) KafkaOpts(extra ...kgo.Opt) ([]kgo.Opt, error) {
	opts := []kgo.Opt{kgo.SeedBrokers(c.Brokers...)}
	if c.TLS {
		opts = append(opts, kgo.DialTLSConfig(&tls.Config{MinVersion: tls.VersionTLS12}))
	}
	switch c.SASLMechanism {
	case "":
	case "SCRAM-SHA-256":
		opts = append(opts, kgo.SASL(scram.Auth{User: c.SASLUsername, Pass: c.SASLPassword}.AsSha256Mechanism()))
	case "SCRAM-SHA-512":
		opts = append(opts, kgo.SASL(scram.Auth{User: c.SASLUsername, Pass: c.SASLPassword}.AsSha512Mechanism()))
	default:
		return nil, fmt.Errorf("REDPANDA_SASL_MECHANISM %q is not supported (use SCRAM-SHA-256 or SCRAM-SHA-512)", c.SASLMechanism)
	}
	return append(opts, extra...), nil
}

// SchemaRegistry returns a Schema Registry client with basic auth when
// credentials are set. Redpanda Cloud accepts the SASL user for the registry
// too, which is why the SR variables default to the SASL ones.
func (c Config) SchemaRegistry() (*sr.Client, error) {
	opts := []sr.ClientOpt{sr.URLs(c.SchemaRegistryURL)}
	if c.SchemaRegistryUser != "" {
		opts = append(opts, sr.BasicAuth(c.SchemaRegistryUser, c.SchemaRegistryPass))
	}
	return sr.NewClient(opts...)
}

// end::clients[]

// Describe is a one-line summary for logs, without the password.
func (c Config) Describe() string {
	auth := "no auth"
	if c.SASLMechanism != "" {
		auth = c.SASLMechanism + " as " + c.SASLUsername
	}
	return fmt.Sprintf("brokers %s (tls=%v, %s), schema registry %s", strings.Join(c.Brokers, ","), c.TLS, auth, c.SchemaRegistryURL)
}
