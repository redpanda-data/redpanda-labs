// The achievements service consumes game.player-events in its own consumer
// group, keeps per-player state in memory (partition-local, because the key
// is player_id), and produces achievement_unlocked events to
// game.achievements.
package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"
	"github.com/twmb/franz-go/pkg/sr"

	"multiplayer-gaming/services/achievements/rules"
	"multiplayer-gaming/services/internal/env"
	"multiplayer-gaming/services/internal/gamepb"
	"multiplayer-gaming/services/internal/schema"
)

type service struct {
	cl       *kgo.Client
	dec      *schema.Decoder
	serde    *sr.Serde
	rules    rules.Rules
	inTopic  string
	outTopic string
	instance string

	mu       sync.Mutex
	players  map[string]*rules.PlayerState
	byPart   map[int32]map[string]struct{}
	unlocked map[string]int64
	produced atomic.Int64
	poison   atomic.Int64
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	brokers := env.List("KAFKA_BROKERS", "redpanda:9092")
	srURL := env.String("SCHEMA_REGISTRY_URL", "http://redpanda:8081")
	schemaFile := env.String("SCHEMA_FILE", "/proto/game_events.proto")
	group := env.String("GROUP", "achievements")
	host, _ := os.Hostname()
	s := &service{
		rules:    rules.Default,
		inTopic:  env.String("TOPIC", "game.player-events"),
		outTopic: env.String("OUT_TOPIC", "game.achievements"),
		instance: host,
		players:  map[string]*rules.PlayerState{},
		byPart:   map[int32]map[string]struct{}{},
		unlocked: map[string]int64{},
	}
	go s.serve(env.String("HTTP_ADDR", ":8080"))

	srClient, err := sr.NewClient(sr.URLs(srURL))
	if err != nil {
		log.Fatalf("schema registry client: %v", err)
	}
	if err := schema.WaitForRegistry(ctx, srClient); err != nil {
		log.Fatal(err)
	}
	text, err := schema.ReadFile(schemaFile)
	if err != nil {
		log.Fatal(err)
	}
	// This service is a producer too: it needs the achievements subject to
	// exist before it writes anything, exactly like the simulator.
	outID, err := schema.WaitForSchema(ctx, srClient, schema.Subject(s.outTopic), text, func() {
		log.Printf("schema for %s not registered yet; run `make schemas`", schema.Subject(s.outTopic))
	})
	if err != nil {
		log.Fatal(err)
	}
	s.serde = schema.NewProducerSerde(outID)
	for {
		s.dec, err = schema.NewDecoder(ctx, srClient, schema.Subject(s.inTopic))
		if err == nil {
			break
		}
		if ctx.Err() != nil {
			return
		}
		log.Printf("waiting for subject %s: %v", schema.Subject(s.inTopic), err)
		time.Sleep(2 * time.Second)
	}

	// tag::consumer[]
	// State lives with the partition. When a rebalance takes partitions away,
	// their players are forgotten here and rebuilt by whichever instance gets
	// them next, from that instance's committed offset onward.
	s.cl, err = kgo.NewClient(
		kgo.SeedBrokers(brokers...),
		kgo.ConsumerGroup(group),
		kgo.ConsumeTopics(s.inTopic),
		kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()),
		kgo.DisableAutoCommit(),
		kgo.RequiredAcks(kgo.AllISRAcks()),
		kgo.RecordPartitioner(kgo.StickyKeyPartitioner(nil)),
		kgo.ClientID("achievements-"+host),
		kgo.OnPartitionsRevoked(func(_ context.Context, _ *kgo.Client, m map[string][]int32) {
			s.mu.Lock()
			defer s.mu.Unlock()
			for _, p := range m[s.inTopic] {
				for pid := range s.byPart[p] {
					delete(s.players, pid)
				}
				delete(s.byPart, p)
			}
			log.Printf("revoked partitions %v, dropped their player state", m[s.inTopic])
		}),
	)
	if err != nil {
		log.Fatalf("kafka client: %v", err)
	}
	defer s.cl.Close()

	for ctx.Err() == nil {
		fetches := s.cl.PollRecords(ctx, 500)
		if fetches.IsClientClosed() || ctx.Err() != nil {
			return
		}
		fetches.EachError(func(t string, p int32, err error) { log.Printf("fetch %s/%d: %v", t, p, err) })
		var batchErr error
		fetches.EachRecord(func(r *kgo.Record) {
			if batchErr == nil {
				batchErr = s.handle(ctx, r)
			}
		})
		if batchErr != nil {
			log.Printf("batch failed, will replay: %v", batchErr)
			time.Sleep(time.Second)
			continue
		}
		if err := s.cl.CommitUncommittedOffsets(ctx); err != nil && ctx.Err() == nil {
			log.Printf("commit: %v", err)
		}
	}
	// end::consumer[]
}

// tag::handle[]
// handle decodes one record, runs the rules, and produces one
// achievement_unlocked event per unlock, keyed by the same player_id so the
// achievements topic is ordered per player too. The offset is committed only
// after those produces are acknowledged.
func (s *service) handle(ctx context.Context, r *kgo.Record) error {
	ev, err := s.dec.Decode(ctx, r.Value)
	if err != nil {
		if errors.Is(err, schema.ErrUnknownSchema) {
			s.poison.Add(1)
			log.Printf("skipping poison record %s/%d@%d", r.Topic, r.Partition, r.Offset)
			return nil
		}
		return err
	}
	if ev.GetPlayerId() == "" {
		return nil
	}
	s.mu.Lock()
	st, ok := s.players[ev.GetPlayerId()]
	if !ok {
		st = rules.NewPlayerState()
		s.players[ev.GetPlayerId()] = st
		if s.byPart[r.Partition] == nil {
			s.byPart[r.Partition] = map[string]struct{}{}
		}
		s.byPart[r.Partition][ev.GetPlayerId()] = struct{}{}
	}
	unlocks := s.rules.Apply(st, ev)
	for _, u := range unlocks {
		s.unlocked[u.Achievement]++
	}
	s.mu.Unlock()

	for _, u := range unlocks {
		out := &gamepb.GameEvent{
			EventId:    achievementID(ev, u),
			PlayerId:   ev.GetPlayerId(),
			MatchId:    ev.GetMatchId(),
			OccurredAt: ev.GetOccurredAt(),
			Region:     ev.Region,
			Event: &gamepb.GameEvent_AchievementUnlocked{AchievementUnlocked: &gamepb.AchievementUnlocked{
				Achievement: u.Achievement, Detail: u.Detail,
			}},
		}
		value, err := s.serde.Encode(out)
		if err != nil {
			return err
		}
		rec := &kgo.Record{
			Topic: s.outTopic,
			Key:   []byte(out.GetPlayerId()),
			Value: value,
			Headers: []kgo.RecordHeader{
				{Key: "event_type", Value: []byte("achievement_unlocked")},
				{Key: "achievement", Value: []byte(u.Achievement)},
			},
		}
		if err := s.cl.ProduceSync(ctx, rec).FirstErr(); err != nil {
			return fmt.Errorf("produce achievement: %w", err)
		}
		s.produced.Add(1)
	}
	return nil
}

// achievementID is stable for a given source event and achievement, so a
// replayed source record produces an achievement with the same event_id.
func achievementID(ev *gamepb.GameEvent, u rules.Unlock) string {
	sum := sha256.Sum256([]byte(ev.GetEventId() + "|" + u.Achievement))
	return "ach-" + hex.EncodeToString(sum[:8])
}

// end::handle[]

func (s *service) serve(addr string) {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		s.mu.Lock()
		unlocked := make(map[string]int64, len(s.unlocked))
		var total int64
		for k, v := range s.unlocked {
			unlocked[k] = v
			total += v
		}
		body := map[string]any{
			"status":          "ok",
			"instance":        s.instance,
			"players_tracked": len(s.players),
			"partitions":      len(s.byPart),
			"unlocked":        unlocked,
			"unlocked_total":  total,
			"produced":        s.produced.Load(),
			"poison_skipped":  s.poison.Load(),
			"ready":           s.dec != nil,
		}
		s.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		_ = enc.Encode(body)
	})
	log.Printf("health on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("http: %v", err)
	}
}
