// Package topics waits for topics that the reader creates by hand.
//
// Every service in this solution starts before `make topics` has run (step 2)
// and refuses to guess: it polls for the topics it needs and logs what it is
// waiting for. Nothing here creates a topic.
package topics

import (
	"context"
	"log"
	"time"

	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"
)

// Wait blocks until every named topic exists or ctx is done.
func Wait(ctx context.Context, cl *kgo.Client, names ...string) {
	adm := kadm.NewClient(cl)
	for {
		listed, err := adm.ListTopics(ctx, names...)
		if err == nil {
			ok := true
			for _, t := range names {
				if !listed.Has(t) {
					ok = false
				}
			}
			if ok {
				return
			}
		}
		log.Printf("topics %v not all present yet; run `make topics`", names)
		select {
		case <-ctx.Done():
			return
		case <-time.After(2 * time.Second):
		}
	}
}
