// The market-state service is the second independent consumer of sports.feed.
// It folds the feed into the trading desk's view of each fixture, which
// markets are open, which are suspended, and whether the provider's sequence
// has holes, and publishes that state to the compacted topic
// sports.market-state.
//
// It publishes state, never deltas. The same state written twice changes
// nothing, so a replay is harmless by construction, and compaction can throw
// away every version but the last without losing the current book. A consumer
// that needs the book at startup reads one compacted record per fixture
// instead of replaying the whole feed.
//
// It is a member of the group `market-state`. It shares the topic with the
// odds engine and the archive pipeline and coordinates with neither.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/hamba/avro/v2"
	"github.com/twmb/franz-go/pkg/kgo"

	"sports-data-fanout/services/internal/conn"
	"sports-data-fanout/services/internal/envvar"
	feedpkg "sports-data-fanout/services/internal/feed"
	"sports-data-fanout/services/internal/topics"
	"sports-data-fanout/services/internal/wire"
	"sports-data-fanout/services/risk/state"
)

type service struct {
	cl       *kgo.Client
	reg      *feedpkg.Registry
	codec    avro.Schema
	schemaID int
	book     *state.Book
	topic    string
	outTopic string
	group    string

	applied   atomic.Int64
	published atomic.Int64
	poison    atomic.Int64
	ready     atomic.Bool
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	host, _ := os.Hostname()
	cfg := conn.FromEnv()
	s := &service{
		book:     state.New(),
		topic:    envvar.String("TOPIC", topics.Feed),
		outTopic: envvar.String("OUT_TOPIC", topics.MarketState),
		group:    envvar.String("GROUP", "market-state"),
	}
	go s.serve(envvar.String("HTTP_ADDR", ":8080"))

	log.Printf("connecting to %s", cfg.Describe())
	srClient, err := cfg.SchemaRegistry()
	if err != nil {
		log.Fatalf("schema registry client: %v", err)
	}
	text, err := feedpkg.ReadFile(envvar.String("STATE_SCHEMA_FILE", "/schemas/market_state.avsc"))
	if err != nil {
		log.Fatal(err)
	}
	s.schemaID, err = feedpkg.WaitForSchema(ctx, srClient, topics.Subject(s.outTopic), text, func() {
		log.Printf("schema for %s not registered yet; run `make schemas`", topics.Subject(s.outTopic))
	})
	if err != nil {
		log.Fatal(err)
	}
	if s.codec, err = avro.Parse(text); err != nil {
		log.Fatalf("parse market state schema: %v", err)
	}
	s.reg = feedpkg.NewRegistry(srClient, topics.Subject(s.topic))

	opts, err := cfg.KafkaOpts(
		kgo.ConsumerGroup(s.group),
		kgo.ConsumeTopics(s.topic),
		kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()),
		kgo.DisableAutoCommit(),
		kgo.BlockRebalanceOnPoll(),
		kgo.RequiredAcks(kgo.AllISRAcks()),
		kgo.RecordPartitioner(kgo.StickyKeyPartitioner(nil)),
		kgo.ClientID("market-state-"+host),
	)
	if err != nil {
		log.Fatal(err)
	}
	if s.cl, err = kgo.NewClient(opts...); err != nil {
		log.Fatalf("kafka client: %v", err)
	}
	topics.Wait(ctx, s.cl, s.topic, s.outTopic)
	if ctx.Err() != nil {
		return
	}
	defer s.cl.CloseAllowingRebalance()
	s.ready.Store(true)
	log.Printf("group %s reading %s, publishing %s under schema id %d", s.group, s.topic, s.outTopic, s.schemaID)

	for ctx.Err() == nil {
		fetches := s.cl.PollRecords(ctx, 500)
		if fetches.IsClientClosed() || ctx.Err() != nil {
			return
		}
		fetches.EachError(func(t string, p int32, err error) { log.Printf("fetch %s/%d: %v", t, p, err) })
		var batchErr error
		fetches.EachRecord(func(r *kgo.Record) {
			if batchErr == nil {
				batchErr = s.apply(ctx, r)
			}
		})
		if err := s.cl.Flush(ctx); err != nil && batchErr == nil {
			batchErr = err
		}
		if batchErr != nil {
			log.Fatalf("batch failed, offsets not committed: %v", batchErr)
		}
		if err := s.cl.CommitUncommittedOffsets(ctx); err != nil {
			log.Printf("commit: %v", err)
		}
		s.cl.AllowRebalance()
	}
}

// tag::apply[]
// apply folds one event into the book and publishes the fixture's new state.
//
// The key is the fixture id, which is what makes compaction meaningful: the
// latest state for a fixture replaces every earlier one.
func (s *service) apply(ctx context.Context, r *kgo.Record) error {
	schemaID, body, err := wire.Decode(r.Value)
	if err != nil {
		s.poison.Add(1)
		log.Printf("poison record at %s/%d offset %d: %v", r.Topic, r.Partition, r.Offset, err)
		return nil
	}
	codec, err := s.reg.Schema(ctx, schemaID)
	if err != nil {
		if errors.Is(err, feedpkg.ErrUnknownSchema) {
			s.poison.Add(1)
			log.Printf("unknown schema id %d at offset %d; skipping", schemaID, r.Offset)
			return nil
		}
		return err
	}
	ev, err := feedpkg.Decode(codec, schemaID, body)
	if err != nil {
		s.poison.Add(1)
		log.Printf("undecodable record at offset %d: %v", r.Offset, err)
		return nil
	}

	fixture := s.book.Apply(ev)
	s.applied.Add(1)

	value, err := avro.Marshal(s.codec, map[string]any{
		"fixture_id":        fixture.FixtureID,
		"open_markets":      int32(fixture.OpenMarkets),
		"suspended_markets": int32(fixture.SuspendedMarkets),
		"last_event_type":   fixture.LastEventType,
		"last_seq":          fixture.LastSeq,
		"gaps":              int32(fixture.Gaps),
		"settled":           fixture.Settled,
		"updated_ts":        fixture.UpdatedTS,
	})
	if err != nil {
		return err
	}
	s.cl.Produce(ctx, &kgo.Record{
		Topic: s.outTopic,
		Key:   []byte(fixture.FixtureID),
		Value: wire.Encode(s.schemaID, value),
	}, func(_ *kgo.Record, err error) {
		if err != nil {
			log.Printf("produce state for %s: %v", fixture.FixtureID, err)
			return
		}
		s.published.Add(1)
	})
	return nil
}

// end::apply[]

func (s *service) serve(addr string) {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		// Always 200: the container is healthy once the process serves, and
		// `make up --wait` has to pass before `make topics` and `make schemas`
		// can create what this service is waiting for. Whether it has work yet
		// is the "ready" field, which the steps and verify.sh read.
		writeJSON(w, map[string]any{
			"ready":     s.ready.Load(),
			"group":     s.group,
			"applied":   s.applied.Load(),
			"published": s.published.Load(),
			"poison":    s.poison.Load(),
			"totals":    s.book.Totals(),
		})
	})
	// The desk's view. One fixture with ?fixture=, everything without.
	mux.HandleFunc("/book", func(w http.ResponseWriter, r *http.Request) {
		if id := r.URL.Query().Get("fixture"); id != "" {
			f, ok := s.book.Get(id)
			if !ok {
				w.WriteHeader(http.StatusNotFound)
				writeJSON(w, map[string]string{"error": "no state for fixture " + id})
				return
			}
			writeJSON(w, f)
			return
		}
		writeJSON(w, s.book.All())
	})
	srv := &http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	if err := srv.ListenAndServe(); err != nil {
		log.Printf("http server: %v", err)
	}
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}
