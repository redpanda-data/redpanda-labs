// The leaderboard service consumes game.player-events in the consumer group
// `leaderboard`, keeps each player's running total in memory, and publishes
// that total to the compacted topic game.leaderboard after every
// score_changed. It publishes state, never deltas: the same total sent twice
// changes nothing, so a replay is harmless by construction. Run more than one
// instance and the group splits the six source partitions between them; each
// instance owns the players on its partitions and nobody else's.
//
// The service serves nothing but /healthz. The dashboard is a separate
// program (services/dashboard) that reads game.leaderboard.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sort"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"
	"github.com/twmb/franz-go/pkg/sr"
	"google.golang.org/protobuf/types/known/timestamppb"

	"multiplayer-gaming/services/internal/board"
	"multiplayer-gaming/services/internal/envvar"
	"multiplayer-gaming/services/internal/gamepb"
	"multiplayer-gaming/services/internal/schema"
	"multiplayer-gaming/services/internal/topics"
)

// player is the in-memory state for one player: the total so far and the
// source offset it was computed up to.
type player struct {
	name      string
	score     int64
	partition int32
	offset    int64 // last game.player-events offset included in score; -1 when none
}

type service struct {
	cl       *kgo.Client
	dec      *schema.Decoder
	serde    *sr.Serde
	brokers  []string
	srURL    string
	group    string
	topic    string
	outTopic string
	instance string

	mu       sync.Mutex
	players  map[string]*player
	byPart   map[int32]map[string]struct{}
	assigned map[int32]bool
	seeded   map[int32]bool

	processed  atomic.Int64
	skipped    atomic.Int64
	poison     atomic.Int64
	duplicates atomic.Int64
	published  atomic.Int64
	produceErr atomic.Value
	ready      atomic.Bool
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	host, _ := os.Hostname()
	s := &service{
		brokers:  envvar.List("KAFKA_BROKERS", "redpanda:9092"),
		srURL:    envvar.String("SCHEMA_REGISTRY_URL", "http://redpanda:8081"),
		group:    envvar.String("GROUP", "leaderboard"),
		topic:    envvar.String("TOPIC", "game.player-events"),
		outTopic: envvar.String("OUT_TOPIC", board.Topic),
		instance: host,
		players:  map[string]*player{},
		byPart:   map[int32]map[string]struct{}{},
		assigned: map[int32]bool{},
		seeded:   map[int32]bool{},
	}
	schemaFile := envvar.String("SCHEMA_FILE", "/proto/game_events.proto")
	go s.serve(envvar.String("HTTP_ADDR", ":8080"))

	srClient, err := sr.NewClient(sr.URLs(s.srURL))
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
	// This service is a producer too: it needs the leaderboard subject to
	// exist before it writes anything, exactly like the simulator.
	outID, err := schema.WaitForSchema(ctx, srClient, schema.Subject(s.outTopic), text, func() {
		log.Printf("schema for %s not registered yet; run `make schemas`", schema.Subject(s.outTopic))
	})
	if err != nil {
		log.Fatal(err)
	}
	s.serde = schema.NewProducerSerde(outID, &gamepb.LeaderboardEntry{}, schema.IndexOf(&gamepb.LeaderboardEntry{}))
	for {
		s.dec, err = schema.NewDecoder(ctx, srClient, schema.Subject(s.topic))
		if err == nil {
			break
		}
		if ctx.Err() != nil {
			return
		}
		log.Printf("waiting for subject %s: %v", schema.Subject(s.topic), err)
		time.Sleep(2 * time.Second)
	}
	// Both topics are created by the reader (step 2). Wait for them before
	// joining the group, so the first fetch is a real one.
	plain, err := kgo.NewClient(kgo.SeedBrokers(s.brokers...), kgo.ClientID("leaderboard-wait-"+host))
	if err != nil {
		log.Fatalf("kafka client: %v", err)
	}
	topics.Wait(ctx, plain, s.topic, s.outTopic)
	plain.Close()
	if ctx.Err() != nil {
		return
	}

	// tag::consumer[]
	// A member of the `leaderboard` group. Offsets are committed by hand after
	// the entries of a batch are acknowledged by the broker, never before: a
	// crash between the publish and the commit replays the batch, and the
	// source offset carried in every entry makes that replay a no-op. A
	// rebalance waits (BlockRebalanceOnPoll) until the batch in hand is
	// published and committed, so a partition never moves with work in flight.
	s.cl, err = kgo.NewClient(
		kgo.SeedBrokers(s.brokers...),
		kgo.ConsumerGroup(s.group),
		kgo.ConsumeTopics(s.topic),
		kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()),
		kgo.DisableAutoCommit(),
		kgo.BlockRebalanceOnPoll(),
		kgo.RequiredAcks(kgo.AllISRAcks()),
		kgo.RecordPartitioner(kgo.StickyKeyPartitioner(nil)),
		kgo.ClientID("leaderboard-"+host),
		kgo.OnPartitionsAssigned(func(_ context.Context, _ *kgo.Client, m map[string][]int32) {
			// State is loaded lazily, on the first record of each partition,
			// so this callback stays quick.
			s.mu.Lock()
			defer s.mu.Unlock()
			for _, p := range m[s.topic] {
				s.assigned[p] = true
			}
			log.Printf("assigned partitions %v", m[s.topic])
		}),
		kgo.OnPartitionsRevoked(func(_ context.Context, _ *kgo.Client, m map[string][]int32) {
			s.mu.Lock()
			defer s.mu.Unlock()
			for _, p := range m[s.topic] {
				for pid := range s.byPart[p] {
					delete(s.players, pid)
				}
				delete(s.byPart, p)
				delete(s.seeded, p)
				delete(s.assigned, p)
			}
			log.Printf("revoked partitions %v, dropped their player state", m[s.topic])
		}),
	)
	if err != nil {
		log.Fatalf("kafka client: %v", err)
	}
	// Leave the group on shutdown so `rpk group seek` sees an empty group at
	// once instead of after the session timeout. With BlockRebalanceOnPoll the
	// plain Close would wait for a rebalance that this loop is blocking.
	defer s.cl.CloseAllowingRebalance()
	s.ready.Store(true)

	for ctx.Err() == nil {
		fetches := s.cl.PollRecords(ctx, 500)
		if fetches.IsClientClosed() || ctx.Err() != nil {
			return
		}
		fetches.EachError(func(t string, p int32, err error) {
			log.Printf("fetch %s/%d: %v", t, p, err)
		})
		var batchErr error
		fetches.EachRecord(func(r *kgo.Record) {
			if batchErr == nil {
				batchErr = s.apply(ctx, r)
			}
		})
		// Wait for every entry of the batch to be acknowledged before the
		// offsets that produced them are committed.
		if err := s.cl.Flush(ctx); err != nil && batchErr == nil {
			batchErr = err
		}
		if pe, _ := s.produceErr.Load().(string); pe != "" && batchErr == nil {
			batchErr = errors.New(pe)
		}
		if batchErr != nil {
			if ctx.Err() != nil {
				return
			}
			// Fail fast. The offsets of this batch are not committed, so the
			// restarted instance fetches it again from the last commit.
			log.Fatalf("batch failed, exiting so the batch is replayed from the last commit: %v", batchErr)
		}
		if err := s.cl.CommitUncommittedOffsets(ctx); err != nil && ctx.Err() == nil {
			log.Printf("commit: %v", err)
		}
		s.cl.AllowRebalance()
	}
	// end::consumer[]
}

// tag::apply[]
// apply folds one record into the player's total and publishes the total.
// Only score_changed moves the board; player_joined supplies the display
// name; everything else is skipped but still committed.
func (s *service) apply(ctx context.Context, r *kgo.Record) error {
	ev, err := s.dec.Decode(ctx, r.Value)
	if err != nil {
		if errors.Is(err, schema.ErrUnknownSchema) {
			s.poison.Add(1)
			log.Printf("skipping poison record %s/%d@%d: %v", r.Topic, r.Partition, r.Offset, err)
			return nil
		}
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.seeded[r.Partition] {
		if err := s.seed(ctx, r.Partition, r.Offset); err != nil {
			return err
		}
	}
	pid := ev.GetPlayerId()
	if pid == "" {
		s.skipped.Add(1)
		return nil
	}
	p := s.players[pid]
	if p == nil {
		p = &player{partition: r.Partition, offset: -1}
		s.players[pid] = p
		if s.byPart[r.Partition] == nil {
			s.byPart[r.Partition] = map[string]struct{}{}
		}
		s.byPart[r.Partition][pid] = struct{}{}
	}
	if j := ev.GetPlayerJoined(); j != nil {
		p.name = j.GetDisplayName()
		s.skipped.Add(1)
		return nil
	}
	sc := ev.GetScoreChanged()
	if sc == nil {
		s.skipped.Add(1)
		return nil
	}
	if r.Offset <= p.offset {
		// Already included in the total this instance loaded from
		// game.leaderboard: a redelivered record after a crash or a rebalance.
		s.duplicates.Add(1)
		return nil
	}
	p.score += sc.GetDelta()
	p.offset = r.Offset
	s.processed.Add(1)
	return s.publish(ctx, pid, p)
}

// publish sends the player's absolute total to game.leaderboard, keyed by
// player_id so compaction keeps the newest one. Produce is asynchronous; the
// consumer loop flushes before it commits.
func (s *service) publish(ctx context.Context, pid string, p *player) error {
	entry := &gamepb.LeaderboardEntry{
		PlayerId:        pid,
		DisplayName:     p.name,
		Score:           p.score,
		UpdatedAt:       timestamppb.Now(),
		SourcePartition: p.partition,
		SourceOffset:    p.offset,
	}
	value, err := s.serde.Encode(entry)
	if err != nil {
		return fmt.Errorf("encode entry: %w", err)
	}
	s.cl.Produce(ctx, &kgo.Record{Topic: s.outTopic, Key: []byte(pid), Value: value}, func(_ *kgo.Record, err error) {
		if err != nil {
			s.produceErr.Store(fmt.Sprintf("produce %s: %v", s.outTopic, err))
			return
		}
		s.published.Add(1)
	})
	return nil
}

// end::apply[]

// tag::seed[]
// seed prepares the state for a partition this instance has just started
// reading, before its first record is applied. firstOffset is where the
// group's committed offset put us. At the start of the log there is nothing
// to load: every record is about to be re-read, so the totals are rebuilt from
// scratch and republished, and the compacted topic converges to the same
// values. Anywhere else, the entries already on game.leaderboard for this
// partition's players are the totals up to their source_offset, and apply
// skips anything at or below it.
func (s *service) seed(ctx context.Context, partition int32, firstOffset int64) error {
	s.seeded[partition] = true
	if firstOffset == 0 {
		log.Printf("partition %d starts at the beginning of the log: rebuilding its totals from scratch", partition)
		return nil
	}
	entries, err := board.Snapshot(ctx, s.brokers, s.srURL, s.outTopic, "leaderboard-seed-"+s.instance)
	if err != nil {
		return fmt.Errorf("load %s: %w", s.outTopic, err)
	}
	n := 0
	for pid, e := range entries {
		if e.GetSourcePartition() != partition {
			continue
		}
		s.players[pid] = &player{name: e.GetDisplayName(), score: e.GetScore(), partition: partition, offset: e.GetSourceOffset()}
		if s.byPart[partition] == nil {
			s.byPart[partition] = map[string]struct{}{}
		}
		s.byPart[partition][pid] = struct{}{}
		n++
	}
	log.Printf("partition %d resumes at offset %d: loaded %d player totals from %s", partition, firstOffset, n, s.outTopic)
	return nil
}

// end::seed[]

func (s *service) status() map[string]any {
	s.mu.Lock()
	parts := make([]int32, 0, len(s.assigned))
	for p := range s.assigned {
		parts = append(parts, p)
	}
	players := len(s.players)
	s.mu.Unlock()
	sort.Slice(parts, func(i, j int) bool { return parts[i] < parts[j] })
	pe, _ := s.produceErr.Load().(string)
	return map[string]any{
		"status":             "ok",
		"instance":           s.instance,
		"group":              s.group,
		"topic":              s.topic,
		"out_topic":          s.outTopic,
		"ready":              s.ready.Load(),
		"partitions":         parts,
		"players":            players,
		"processed":          s.processed.Load(),
		"published":          s.published.Load(),
		"skipped":            s.skipped.Load(),
		"poison_skipped":     s.poison.Load(),
		"duplicates_skipped": s.duplicates.Load(),
		"produce_error":      pe,
	}
}

func (s *service) serve(addr string) {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		_ = enc.Encode(s.status())
	})
	log.Printf("health on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("http: %v", err)
	}
}
