// Package topics names the topics this solution reads and writes. One place,
// so a rename cannot leave a consumer reading a topic nobody writes.
package topics

import (
	"context"
	"log"
	"time"

	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"

	"sports-data-fanout/services/internal/envvar"
)

const (
	// Feed is the provider's raw event stream, keyed by fixture id.
	Feed = "sports.feed"
	// Odds is the priced output of the odds engine, keyed by market id.
	Odds = "sports.odds"
	// MarketState is the trading desk's current view, compacted by fixture id.
	MarketState = "sports.market-state"
)

// Subject is the Schema Registry subject holding a topic's value schema.
func Subject(topic string) string { return topic + "-value" }

// FromEnv lets a container override one topic name without a rebuild, which
// is what the "run two stacks side by side" note in .env.example relies on.
func FromEnv(key, def string) string { return envvar.String(key, def) }

// tag::wait[]
// Wait blocks until every named topic exists, so a service joins its group
// with something to read instead of racing `make topics`.
func Wait(ctx context.Context, cl *kgo.Client, names ...string) {
	adm := kadm.NewClient(cl)
	for {
		missing := names
		if details, err := adm.ListTopics(ctx, names...); err == nil {
			missing = nil
			for _, name := range names {
				if d, ok := details[name]; !ok || d.Err != nil {
					missing = append(missing, name)
				}
			}
		}
		if len(missing) == 0 {
			return
		}
		log.Printf("waiting for topics %v; run `make topics`", missing)
		select {
		case <-ctx.Done():
			return
		case <-time.After(2 * time.Second):
		}
	}
}

// end::wait[]
