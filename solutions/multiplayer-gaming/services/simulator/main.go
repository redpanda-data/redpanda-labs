// The game simulator stands in for game servers. It produces a deterministic
// stream of GameEvent records to game.player-events and game.match-events,
// stops at SIM_EVENTS_MAX so counts are exact, and exposes a small admin API
// on :8090 (/stats, POST /burst, POST /poison) for the later steps.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"
	"github.com/twmb/franz-go/pkg/sr"

	"multiplayer-gaming/services/internal/envvar"
	"multiplayer-gaming/services/internal/gamepb"
	"multiplayer-gaming/services/internal/schema"
	"multiplayer-gaming/services/simulator/sim"
)

type stats struct {
	State       string           `json:"state"`
	Seed        int64            `json:"seed"`
	Players     int              `json:"players"`
	Rate        int              `json:"rate_per_second"`
	EventsMax   int64            `json:"events_max"`
	Generated   int64            `json:"generated_total"`
	Acked       map[string]int64 `json:"acked"`
	AckedTotal  int64            `json:"acked_total"`
	Errors      int64            `json:"produce_errors"`
	BurstEvents int64            `json:"burst_events"`
	Poison      int64            `json:"poison_records"`
	ByType      map[string]int64 `json:"events_by_type"`
	SimTime     string           `json:"sim_time"`
	SchemaIDs   map[string]int   `json:"schema_ids"`
}

type simulator struct {
	cl     *kgo.Client
	gen    *sim.Generator
	serdes map[string]*schemaSerde
	rate   int
	max    int64
	stMu   sync.Mutex
	st     stats

	acked   map[string]*atomic.Int64
	errs    atomic.Int64
	poison  atomic.Int64
	genN    atomic.Int64
	burstN  atomic.Int64
	burstMu sync.Mutex
	burst   *burstReq
}

type schemaSerde struct {
	id    int
	serde *sr.Serde
}

type burstReq struct {
	rate     int
	deadline time.Time
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	brokers := envvar.List("KAFKA_BROKERS", "redpanda:9092")
	srURL := envvar.String("SCHEMA_REGISTRY_URL", "http://redpanda:8081")
	schemaFile := envvar.String("SCHEMA_FILE", "/proto/game_events.proto")
	playersFile := envvar.String("PLAYERS_FILE", "/sample-data/players.json")
	httpAddr := envvar.String("HTTP_ADDR", ":8090")

	cfg := sim.Config{
		Seed:          envvar.Int64("SIM_SEED", 42),
		Players:       envvar.Int("SIM_PLAYERS", 24),
		MatchDuration: time.Duration(envvar.Int("SIM_MATCH_DURATION", 60)) * time.Second,
		Tick:          time.Duration(envvar.Int("SIM_TICK_MS", 200)) * time.Millisecond,
		Region:        envvar.String("SIM_REGION", "eu-west"),
	}
	if b, err := os.ReadFile(playersFile); err == nil {
		if err := json.Unmarshal(b, &cfg.Roster); err != nil {
			log.Fatalf("parse %s: %v", playersFile, err)
		}
	} else {
		log.Printf("no roster at %s (%v); using synthetic names", playersFile, err)
	}

	s := &simulator{
		gen:    sim.New(cfg),
		serdes: map[string]*schemaSerde{},
		rate:   envvar.Int("SIM_RATE", 100),
		max:    envvar.Int64("SIM_EVENTS_MAX", 3000),
		acked: map[string]*atomic.Int64{
			sim.TopicPlayerEvents: {},
			sim.TopicMatchEvents:  {},
		},
	}
	s.st = stats{State: "starting", Seed: cfg.Seed, Players: cfg.Players, Rate: s.rate, EventsMax: s.max}

	// tag::producer[]
	// One producer for both topics. Idempotence is on by default in franz-go
	// (a broker-side sequence number per partition drops retried duplicates),
	// acks=all waits for the full in-sync replica set, and the sticky key
	// partitioner hashes the record key the same way the Java client does, so
	// every event of one player lands on one partition, in order.
	cl, err := kgo.NewClient(
		kgo.SeedBrokers(brokers...),
		kgo.RequiredAcks(kgo.AllISRAcks()),
		kgo.RecordPartitioner(kgo.StickyKeyPartitioner(nil)),
		kgo.ProducerBatchCompression(kgo.SnappyCompression()),
		kgo.ProducerLinger(5*time.Millisecond),
		kgo.ClientID("game-simulator"),
	)
	if err != nil {
		log.Fatalf("kafka client: %v", err)
	}
	defer cl.Close()
	s.cl = cl
	// end::producer[]

	go s.serve(httpAddr)

	// Refuse to produce until the topics and the schema contract exist. Both
	// are created by the reader (steps 2 and 3), not by this service.
	s.setState("waiting_for_topics")
	waitForTopics(ctx, cl, sim.TopicPlayerEvents, sim.TopicMatchEvents)

	s.setState("waiting_for_schema")
	srClient, err := sr.NewClient(sr.URLs(srURL))
	if err != nil {
		log.Fatalf("schema registry client: %v", err)
	}
	text, err := schema.ReadFile(schemaFile)
	if err != nil {
		log.Fatal(err)
	}
	ids := map[string]int{}
	for _, topic := range []string{sim.TopicPlayerEvents, sim.TopicMatchEvents} {
		subject := schema.Subject(topic)
		id, err := schema.WaitForSchema(ctx, srClient, subject, text, func() {
			log.Printf("schema for %s not registered yet; run `make schemas`", subject)
		})
		if err != nil {
			log.Fatalf("schema lookup: %v", err)
		}
		s.serdes[topic] = &schemaSerde{id: id, serde: schema.NewProducerSerde(id)}
		ids[subject] = id
		log.Printf("%s -> schema id %d", subject, id)
	}
	s.stMu.Lock()
	s.st.SchemaIDs = ids
	s.stMu.Unlock()

	s.run(ctx)
	log.Println("flushing")
	_ = cl.Flush(context.Background())
}

func waitForTopics(ctx context.Context, cl *kgo.Client, topics ...string) {
	adm := kadm.NewClient(cl)
	for {
		listed, err := adm.ListTopics(ctx, topics...)
		if err == nil {
			ok := true
			for _, t := range topics {
				if !listed.Has(t) {
					ok = false
				}
			}
			if ok {
				return
			}
		}
		log.Printf("topics %v not all present yet; run `make topics`", topics)
		select {
		case <-ctx.Done():
			return
		case <-time.After(2 * time.Second):
		}
	}
}

// tag::loop[]
// run paces the generator at SIM_RATE events per second until SIM_EVENTS_MAX,
// then idles. A burst (POST /burst) resumes production at a higher rate for a
// fixed time; those events are counted separately so verify.sh can still
// reason about the seeded set.
func (s *simulator) run(ctx context.Context) {
	for ctx.Err() == nil {
		rate := s.rate
		bursting := false
		if b := s.currentBurst(); b != nil {
			rate, bursting = b.rate, true
		}
		if !bursting && s.genN.Load() >= s.max {
			s.setState("capped")
			time.Sleep(200 * time.Millisecond)
			continue
		}
		if bursting {
			s.setState("bursting")
		} else {
			s.setState("producing")
		}
		interval := time.Second / time.Duration(rate)
		ticker := time.NewTicker(interval)
		for ctx.Err() == nil {
			<-ticker.C
			if b := s.currentBurst(); bursting && b == nil {
				break // burst over, back to the normal rate (or the cap)
			}
			if !bursting && s.genN.Load() >= s.max {
				break
			}
			if !bursting && s.currentBurst() != nil {
				break // switch to the burst rate
			}
			s.produceOne(ctx, bursting)
		}
		ticker.Stop()
	}
}

func (s *simulator) produceOne(ctx context.Context, burst bool) {
	ev := s.gen.Next()
	s.genN.Add(1)
	if burst {
		s.burstN.Add(1)
	}
	topic := sim.Topic(ev)
	value, err := s.serdes[topic].serde.Encode(ev)
	if err != nil {
		log.Printf("encode: %v", err)
		s.errs.Add(1)
		return
	}
	rec := &kgo.Record{
		Topic: topic,
		Key:   []byte(sim.Key(ev)),
		Value: value,
		Headers: []kgo.RecordHeader{
			{Key: "event_type", Value: []byte(sim.EventType(ev))},
		},
	}
	s.cl.Produce(ctx, rec, func(r *kgo.Record, err error) {
		if err != nil {
			s.errs.Add(1)
			log.Printf("produce %s: %v", r.Topic, err)
			return
		}
		s.acked[r.Topic].Add(1)
	})
}

// end::loop[]

// tag::poison[]
// Poison writes one record whose schema ID (2147483647) is registered nowhere.
// Every consumer of game.player-events has to decide what to do with it: the
// Go services log and skip it, Redpanda Connect routes it to
// game.player-events.dlq through its fallback output.
func (s *simulator) producePoison(ctx context.Context) error {
	value := []byte{0, 0x7f, 0xff, 0xff, 0xff, 0, 0xde, 0xad, 0xbe, 0xef}
	rec := &kgo.Record{
		Topic:   sim.TopicPlayerEvents,
		Key:     []byte("poison"),
		Value:   value,
		Headers: []kgo.RecordHeader{{Key: "event_type", Value: []byte("poison")}},
	}
	if err := s.cl.ProduceSync(ctx, rec).FirstErr(); err != nil {
		return err
	}
	s.poison.Add(1)
	return nil
}

// end::poison[]

func (s *simulator) currentBurst() *burstReq {
	s.burstMu.Lock()
	defer s.burstMu.Unlock()
	if s.burst != nil && time.Now().After(s.burst.deadline) {
		s.burst = nil
	}
	return s.burst
}

func (s *simulator) setState(state string) {
	s.stMu.Lock()
	s.st.State = state
	s.stMu.Unlock()
}

func (s *simulator) snapshot() stats {
	s.stMu.Lock()
	out := stats{
		State: s.st.State, Seed: s.st.Seed, Players: s.st.Players, Rate: s.st.Rate,
		EventsMax: s.st.EventsMax, SchemaIDs: s.st.SchemaIDs,
	}
	s.stMu.Unlock()
	out.Generated = s.genN.Load()
	out.Acked = map[string]int64{}
	for t, c := range s.acked {
		out.Acked[t] = c.Load()
		out.AckedTotal += c.Load()
	}
	out.Errors = s.errs.Load()
	out.BurstEvents = s.burstN.Load()
	out.Poison = s.poison.Load()
	out.ByType = s.gen.Counts()
	out.SimTime = s.gen.Now().Format(time.RFC3339)
	return out
}

func (s *simulator) serve(addr string) {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("/stats", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, s.snapshot())
	})
	mux.HandleFunc("/burst", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "POST only", http.StatusMethodNotAllowed)
			return
		}
		rate, _ := strconv.Atoi(r.URL.Query().Get("rate"))
		secs, _ := strconv.Atoi(r.URL.Query().Get("seconds"))
		if rate <= 0 || rate > 20000 || secs <= 0 || secs > 600 {
			http.Error(w, "need rate=1..20000 and seconds=1..600", http.StatusBadRequest)
			return
		}
		s.burstMu.Lock()
		s.burst = &burstReq{rate: rate, deadline: time.Now().Add(time.Duration(secs) * time.Second)}
		s.burstMu.Unlock()
		writeJSON(w, map[string]any{"burst": "started", "rate_per_second": rate, "seconds": secs, "events": rate * secs})
	})
	mux.HandleFunc("/poison", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "POST only", http.StatusMethodNotAllowed)
			return
		}
		if err := s.producePoison(r.Context()); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, map[string]any{"poison": "produced", "topic": sim.TopicPlayerEvents, "schema_id": 2147483647, "total": s.poison.Load()})
	})
	log.Printf("admin API on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("http: %v", err)
	}
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	if err := enc.Encode(v); err != nil {
		fmt.Fprintln(os.Stderr, err)
	}
}

var _ = gamepb.GameEvent{}
