// The odds engine is the first of three independent consumers of sports.feed.
// It prices every market update and publishes the result to sports.odds, and
// it measures how long that took from the moment the provider emitted the
// event.
//
// It is a member of the consumer group `odds-engine`. Nothing it does affects
// the other two consumers: they have their own group, their own offsets, and
// their own idea of how far behind they are. That independence is the whole
// argument for a log in front of a feed, instead of the provider's HTTP
// endpoint that every consumer has to share.
//
// Offsets are committed by hand after the prices of a batch are acknowledged,
// so a crash between publishing and committing replays the batch. A replayed
// price is the same price: the record is keyed by market and carries the feed
// sequence it came from, so a consumer can tell current from stale without a
// clock, and a duplicate changes nothing.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sort"
	"strconv"
	"sync"
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
	"sports-data-fanout/services/odds/pricing"
)

type service struct {
	cl        *kgo.Client
	reg       *feedpkg.Registry
	oddsCodec avro.Schema
	oddsID    int
	topic     string
	outTopic  string
	group     string

	mu        sync.Mutex
	suspended map[string]bool // market id -> suspended
	latency   []int64         // priced_ts - feed_ts, milliseconds
	versions  map[int]int64   // writer schema id -> events seen

	read     atomic.Int64
	priced   atomic.Int64
	skipped  atomic.Int64
	suspends atomic.Int64
	rejected atomic.Int64
	poison   atomic.Int64
	ready    atomic.Bool
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	host, _ := os.Hostname()
	cfg := conn.FromEnv()
	s := &service{
		topic:     envvar.String("TOPIC", topics.Feed),
		outTopic:  envvar.String("OUT_TOPIC", topics.Odds),
		group:     envvar.String("GROUP", "odds-engine"),
		suspended: map[string]bool{},
		versions:  map[int]int64{},
	}
	go s.serve(envvar.String("HTTP_ADDR", ":8080"))

	log.Printf("connecting to %s", cfg.Describe())
	srClient, err := cfg.SchemaRegistry()
	if err != nil {
		log.Fatalf("schema registry client: %v", err)
	}
	oddsText, err := feedpkg.ReadFile(envvar.String("ODDS_SCHEMA_FILE", "/schemas/odds.avsc"))
	if err != nil {
		log.Fatal(err)
	}
	s.oddsID, err = feedpkg.WaitForSchema(ctx, srClient, topics.Subject(s.outTopic), oddsText, func() {
		log.Printf("schema for %s not registered yet; run `make schemas`", topics.Subject(s.outTopic))
	})
	if err != nil {
		log.Fatal(err)
	}
	if s.oddsCodec, err = avro.Parse(oddsText); err != nil {
		log.Fatalf("parse odds schema: %v", err)
	}
	// The source subject is read through a Registry rather than one schema:
	// while a provider's change is rolling out, both versions are in the topic.
	s.reg = feedpkg.NewRegistry(srClient, topics.Subject(s.topic))

	opts, err := cfg.KafkaOpts(
		kgo.ConsumerGroup(s.group),
		kgo.ConsumeTopics(s.topic),
		kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()),
		kgo.DisableAutoCommit(),
		kgo.BlockRebalanceOnPoll(),
		kgo.RequiredAcks(kgo.AllISRAcks()),
		kgo.RecordPartitioner(kgo.StickyKeyPartitioner(nil)),
		kgo.ClientID("odds-engine-"+host),
		kgo.OnPartitionsAssigned(func(_ context.Context, _ *kgo.Client, m map[string][]int32) {
			log.Printf("assigned partitions %v", m[s.topic])
		}),
		kgo.OnPartitionsRevoked(func(_ context.Context, _ *kgo.Client, m map[string][]int32) {
			// Suspension state belongs to the partitions this member owns. On
			// revoke it goes with them, or a market stays suspended here after
			// another member has resumed it.
			s.mu.Lock()
			defer s.mu.Unlock()
			s.suspended = map[string]bool{}
			log.Printf("revoked partitions %v, dropped market state", m[s.topic])
		}),
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
	log.Printf("group %s reading %s, publishing %s under schema id %d", s.group, s.topic, s.outTopic, s.oddsID)

	// tag::loop[]
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
			// Do not commit: the batch replays. Exiting is the honest response
			// to a broker that would not take a price.
			log.Fatalf("batch failed, offsets not committed: %v", batchErr)
		}
		if err := s.cl.CommitUncommittedOffsets(ctx); err != nil {
			log.Printf("commit: %v", err)
		}
		s.cl.AllowRebalance()
	}
	// end::loop[]
}

// tag::apply[]
// apply prices one feed record, if it is priceable, and queues the result.
func (s *service) apply(ctx context.Context, r *kgo.Record) error {
	// Counted before anything can classify or reject it, so priced + skipped
	// + held_suspended + rejected + poison must add up to exactly this. A
	// record that falls through every branch shows up as a gap in that sum.
	s.read.Add(1)
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

	s.mu.Lock()
	s.versions[schemaID]++
	switch ev.EventType {
	case feedpkg.TypeMarketSuspend:
		s.suspended[ev.MarketID] = true
	case feedpkg.TypeMarketResume:
		delete(s.suspended, ev.MarketID)
	}
	suspended := s.suspended[ev.MarketID]
	s.mu.Unlock()

	price, err := pricing.Price(ev, suspended)
	switch {
	case errors.Is(err, pricing.ErrNotPriceable):
		s.skipped.Add(1)
		return nil
	case errors.Is(err, pricing.ErrSuspended):
		s.suspends.Add(1)
		return nil
	case errors.Is(err, pricing.ErrOutOfRange):
		// The provider sent a probability that cannot be a price. Counted and
		// logged, never published: a wrong price is worse than no price.
		s.rejected.Add(1)
		log.Printf("rejected %s %s: probability %v", ev.MarketID, ev.Selection, ev.Probability)
		return nil
	case err != nil:
		return err
	}

	pricedTS := time.Now().UnixMilli()
	out := map[string]any{
		"market_id":        ev.MarketID,
		"fixture_id":       ev.FixtureID,
		"selection":        ev.Selection,
		"price":            price,
		"feed_seq":         ev.Seq,
		"feed_ts":          ev.FeedTS,
		"priced_ts":        pricedTS,
		"writer_schema_id": int32(schemaID),
	}
	value, err := avro.Marshal(s.oddsCodec, out)
	if err != nil {
		return err
	}
	s.cl.Produce(ctx, &kgo.Record{
		Topic: s.outTopic,
		Key:   []byte(ev.MarketID),
		Value: wire.Encode(s.oddsID, value),
	}, func(_ *kgo.Record, err error) {
		if err != nil {
			log.Printf("produce odds for %s: %v", ev.MarketID, err)
			return
		}
		s.priced.Add(1)
	})
	s.record(pricedTS - ev.FeedTS)
	return nil
}

// end::apply[]

// record keeps the end-to-end latency samples the /latency endpoint reports.
// The window is bounded because this is a demonstration, not a metrics system:
// the last 10000 samples are enough to see a percentile move.
func (s *service) record(ms int64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.latency = append(s.latency, ms)
	if len(s.latency) > 10000 {
		s.latency = s.latency[len(s.latency)-10000:]
	}
}

type latencyReport struct {
	Samples int   `json:"samples"`
	P50     int64 `json:"p50_ms"`
	P95     int64 `json:"p95_ms"`
	P99     int64 `json:"p99_ms"`
	Max     int64 `json:"max_ms"`
}

// tag::percentiles[]
// percentiles is the end-to-end latency from the provider's emit time to the
// moment the price was published: feed_ts to priced_ts, across the whole path.
// It is not the broker's write latency, and it includes the consumer's own
// batching, which is the number a trading desk cares about.
func (s *service) percentiles() latencyReport {
	s.mu.Lock()
	samples := append([]int64(nil), s.latency...)
	s.mu.Unlock()
	if len(samples) == 0 {
		return latencyReport{}
	}
	sort.Slice(samples, func(i, j int) bool { return samples[i] < samples[j] })
	at := func(q float64) int64 {
		i := int(q * float64(len(samples)-1))
		return samples[i]
	}
	return latencyReport{
		Samples: len(samples),
		P50:     at(0.50),
		P95:     at(0.95),
		P99:     at(0.99),
		Max:     samples[len(samples)-1],
	}
}

// end::percentiles[]

func (s *service) serve(addr string) {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		// Always 200: the container is healthy once the process serves, and
		// `make up --wait` has to pass before `make topics` and `make schemas`
		// can create what this service is waiting for. Whether it has work yet
		// is the "ready" field, which the steps and verify.sh read.
		s.mu.Lock()
		versions := map[string]int64{}
		for id, n := range s.versions {
			versions[strconv.Itoa(id)] = n
		}
		s.mu.Unlock()
		writeJSON(w, map[string]any{
			"ready":            s.ready.Load(),
			"group":            s.group,
			"read":             s.read.Load(),
			"priced":           s.priced.Load(),
			"skipped":          s.skipped.Load(),
			"held_suspended":   s.suspends.Load(),
			"rejected":         s.rejected.Load(),
			"poison":           s.poison.Load(),
			"by_writer_schema": versions,
			"latency":          s.percentiles(),
		})
	})
	mux.HandleFunc("/latency", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.percentiles())
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
