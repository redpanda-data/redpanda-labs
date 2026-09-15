// The feed service stands in for a sports data provider's push feed. It
// produces events to sports.feed keyed by fixture id, at a rate it is told,
// under a schema it looks up but never registers.
//
// Two things about it are not decoration:
//
//   - The key is the fixture id, so every event for one match lands on one
//     partition and arrives at every consumer in the provider's order. Ordering
//     per fixture is the only ordering a sportsbook actually needs, and keying
//     by fixture is what buys it without giving up parallelism.
//   - It writes with RequiredAcks(all) and waits for each batch. A feed that
//     reports success before the cluster has the event is a feed that loses
//     events under exactly the load that matters.
//
// It serves /healthz (counters) and /events (the last few events, so a reader
// can see the shape without a consumer).
package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/hamba/avro/v2"
	"github.com/twmb/franz-go/pkg/kgo"

	"sports-data-fanout/services/feed/sim"
	"sports-data-fanout/services/internal/conn"
	"sports-data-fanout/services/internal/envvar"
	feedpkg "sports-data-fanout/services/internal/feed"
	"sports-data-fanout/services/internal/topics"
	"sports-data-fanout/services/internal/wire"
)

type service struct {
	cl    *kgo.Client
	topic string

	produced atomic.Int64
	failed   atomic.Int64
	ready    atomic.Bool
	done     atomic.Bool
	schemaID atomic.Int64

	mu     sync.Mutex
	recent []feedpkg.Event
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	cfg := conn.FromEnv()
	s := &service{topic: envvar.String("TOPIC", topics.Feed)}
	go s.serve(envvar.String("HTTP_ADDR", ":8080"))

	schemaFile := envvar.String("SCHEMA_FILE", "/schemas/feed_event.avsc")
	fixturesFile := envvar.String("FIXTURES_FILE", "/sample-data/fixtures.json")
	rate := envvar.Int("FEED_RATE", 200)
	maxEvents := envvar.Int("FEED_EVENTS_MAX", 4000)

	log.Printf("connecting to %s", cfg.Describe())
	srClient, err := cfg.SchemaRegistry()
	if err != nil {
		log.Fatalf("schema registry client: %v", err)
	}
	schemaText, err := feedpkg.ReadFile(schemaFile)
	if err != nil {
		log.Fatal(err)
	}
	subject := topics.Subject(s.topic)
	// The contract must exist first. A producer that registers its own schema
	// makes itself the source of truth for a shape nobody reviewed.
	schemaID, err := feedpkg.WaitForSchema(ctx, srClient, subject, schemaText, func() {
		log.Printf("schema for %s not registered yet; run `make schemas`", subject)
	})
	if err != nil {
		log.Fatal(err)
	}
	s.schemaID.Store(int64(schemaID))
	codec, err := avro.Parse(schemaText)
	if err != nil {
		log.Fatalf("parse %s: %v", schemaFile, err)
	}
	// Whether this file is the version with the provider field decides what
	// the producer writes, so it is read from the schema rather than a flag.
	withProvider := hasField(codec, "provider")

	fixtures, err := loadFixtures(fixturesFile)
	if err != nil {
		log.Fatal(err)
	}
	gen, err := sim.New(sim.Config{
		Seed:             int64(envvar.Int("FEED_SEED", 42)),
		Fixtures:         fixtures,
		Provider:         envvar.String("FEED_PROVIDER", "sportradar"),
		SuspendEvery:     envvar.Int("FEED_SUSPEND_EVERY", 11),
		DropEvery:        envvar.Int("FEED_DROP_EVERY", 0),
		EventsPerFixture: int64(envvar.Int("FEED_EVENTS_PER_FIXTURE", 250)),
	})
	if err != nil {
		log.Fatal(err)
	}

	opts, err := cfg.KafkaOpts(
		kgo.RequiredAcks(kgo.AllISRAcks()),
		kgo.RecordPartitioner(kgo.StickyKeyPartitioner(nil)),
		kgo.ClientID("sports-feed"),
	)
	if err != nil {
		log.Fatal(err)
	}
	s.cl, err = kgo.NewClient(opts...)
	if err != nil {
		log.Fatalf("kafka client: %v", err)
	}
	defer s.cl.Close()
	topics.Wait(ctx, s.cl, s.topic)
	if ctx.Err() != nil {
		return
	}
	s.ready.Store(true)
	log.Printf("producing to %s under schema id %d (provider field: %v), %d events/s, stopping after %d",
		s.topic, schemaID, withProvider, rate, maxEvents)

	interval := time.Second / time.Duration(max(rate, 1))
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for ctx.Err() == nil {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		ev, ok := gen.Next(time.Now().UnixMilli())
		if !ok {
			log.Printf("every fixture has ended after %d events", s.produced.Load())
			s.done.Store(true)
			<-ctx.Done()
			return
		}
		if err := s.publish(ctx, codec, schemaID, ev, withProvider); err != nil {
			s.failed.Add(1)
			log.Printf("publish %s seq %d: %v", ev.FixtureID, ev.Seq, err)
			continue
		}
		if int(s.produced.Load()) >= maxEvents {
			log.Printf("reached FEED_EVENTS_MAX=%d", maxEvents)
			s.done.Store(true)
			<-ctx.Done()
			return
		}
	}
}

// tag::publish[]
// publish writes one event and waits for the broker to acknowledge it.
//
// The key is the fixture, never the market: markets belong to a fixture, and
// splitting them across partitions would let a suspension overtake the price
// it suspends.
func (s *service) publish(ctx context.Context, codec avro.Schema, schemaID int, ev feedpkg.Event, withProvider bool) error {
	body, err := feedpkg.Encode(codec, ev, withProvider)
	if err != nil {
		return err
	}
	rec := &kgo.Record{
		Topic: s.topic,
		Key:   []byte(ev.FixtureID),
		Value: wire.Encode(schemaID, body),
		Headers: []kgo.RecordHeader{
			{Key: "event_type", Value: []byte(ev.EventType)},
		},
	}
	if err := s.cl.ProduceSync(ctx, rec).FirstErr(); err != nil {
		return err
	}
	s.produced.Add(1)
	s.remember(ev)
	return nil
}

// end::publish[]

func (s *service) remember(ev feedpkg.Event) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.recent = append(s.recent, ev)
	if len(s.recent) > 20 {
		s.recent = s.recent[len(s.recent)-20:]
	}
}

// hasField reports whether a record schema carries a field. The producer asks
// the schema what it can write rather than being told by a flag, so the file
// and the records cannot disagree.
func hasField(sch avro.Schema, name string) bool {
	rec, ok := sch.(*avro.RecordSchema)
	if !ok {
		return false
	}
	for _, f := range rec.Fields() {
		if f.Name() == name {
			return true
		}
	}
	return false
}

func loadFixtures(path string) ([]sim.Fixture, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var out []sim.Fixture
	if err := json.Unmarshal(b, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func (s *service) serve(addr string) {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		// Always 200: the container is healthy once the process serves, and
		// `make up --wait` has to pass before `make topics` and `make schemas`
		// can create what this service is waiting for. Whether it has work yet
		// is the "ready" field, which the steps and verify.sh read.
		writeJSON(w, map[string]any{
			"ready":     s.ready.Load(),
			"done":      s.done.Load(),
			"produced":  s.produced.Load(),
			"failed":    s.failed.Load(),
			"schema_id": s.schemaID.Load(),
			"topic":     s.topic,
		})
	})
	mux.HandleFunc("/events", func(w http.ResponseWriter, r *http.Request) {
		s.mu.Lock()
		recent := append([]feedpkg.Event(nil), s.recent...)
		s.mu.Unlock()
		writeJSON(w, recent)
	})
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Printf("http server: %v", err)
	}
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}
