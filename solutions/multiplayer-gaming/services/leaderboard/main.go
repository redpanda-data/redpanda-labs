// The leaderboard service consumes game.player-events in the consumer group
// `leaderboard` and applies every score_changed delta to Redis sorted sets.
// Run more than one instance and the group splits the six partitions between
// them. The same binary started with LEADERBOARD_ROLE=dashboard joins no
// group: it only reads Redis and the group's lag and serves the dashboard on
// a fixed port, so scaling the consumers never moves the dashboard's address.
package main

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"
	"github.com/twmb/franz-go/pkg/sr"

	"multiplayer-gaming/services/internal/envvar"
	"multiplayer-gaming/services/internal/gamepb"
	"multiplayer-gaming/services/internal/schema"
)

//go:embed static/index.html
var static embed.FS

const globalKey = "leaderboard:global"

func matchKey(id string) string { return "leaderboard:match:" + id }

type service struct {
	rdb      *redis.Client
	cl       *kgo.Client
	adm      *kadm.Client
	dec      *schema.Decoder
	group    string
	topic    string
	instance string
	role     string
	dedup    bool

	processed atomic.Int64
	skipped   atomic.Int64
	poison    atomic.Int64
	dupes     atomic.Int64
	lag       atomic.Int64
	members   atomic.Int64
	lagErr    atomic.Value
	assigned  sync.Map // partition -> struct{}
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	brokers := envvar.List("KAFKA_BROKERS", "redpanda:9092")
	srURL := envvar.String("SCHEMA_REGISTRY_URL", "http://redpanda:8081")
	host, _ := os.Hostname()
	s := &service{
		group:    envvar.String("GROUP", "leaderboard"),
		topic:    envvar.String("TOPIC", "game.player-events"),
		instance: host,
		role:     envvar.String("LEADERBOARD_ROLE", "consumer"),
		dedup:    envvar.Bool("LEADERBOARD_DEDUP", false),
	}
	s.lagErr.Store("")

	s.rdb = redis.NewClient(&redis.Options{Addr: envvar.String("REDIS_ADDR", "redis:6379")})
	if err := s.rdb.Ping(ctx).Err(); err != nil {
		log.Fatalf("redis: %v", err)
	}

	go s.serve(envvar.String("HTTP_ADDR", ":8080"))

	if s.role == "dashboard" {
		// No consumer group membership: a plain client for the admin API, so
		// the lag and member count shown are the consumers', not ours.
		cl, err := kgo.NewClient(kgo.SeedBrokers(brokers...), kgo.ClientID("leaderboard-dashboard"))
		if err != nil {
			log.Fatalf("kafka client: %v", err)
		}
		defer cl.Close()
		s.adm = kadm.NewClient(cl)
		s.watchLag(ctx)
		return
	}

	srClient, err := sr.NewClient(sr.URLs(srURL))
	if err != nil {
		log.Fatalf("schema registry client: %v", err)
	}
	if err := schema.WaitForRegistry(ctx, srClient); err != nil {
		log.Fatal(err)
	}
	// The subject exists once step 3 has run. Until then there is nothing to
	// decode, so wait rather than guess.
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

	// tag::consumer[]
	// A member of the `leaderboard` group. Offsets are committed by hand after
	// the Redis writes of a batch succeed, never before: a crash between the
	// write and the commit replays the batch (at-least-once), a crash between
	// the commit and the write would lose it.
	s.cl, err = kgo.NewClient(
		kgo.SeedBrokers(brokers...),
		kgo.ConsumerGroup(s.group),
		kgo.ConsumeTopics(s.topic),
		kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()),
		kgo.DisableAutoCommit(),
		kgo.ClientID("leaderboard-"+host),
		kgo.OnPartitionsAssigned(func(_ context.Context, _ *kgo.Client, m map[string][]int32) {
			for _, ps := range m[s.topic] {
				s.assigned.Store(ps, struct{}{})
			}
			log.Printf("assigned partitions %v", m[s.topic])
		}),
		kgo.OnPartitionsRevoked(func(_ context.Context, _ *kgo.Client, m map[string][]int32) {
			for _, ps := range m[s.topic] {
				s.assigned.Delete(ps)
			}
			log.Printf("revoked partitions %v", m[s.topic])
		}),
	)
	if err != nil {
		log.Fatalf("kafka client: %v", err)
	}
	defer s.cl.Close()
	s.adm = kadm.NewClient(s.cl)
	go s.watchLag(ctx)

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
			if batchErr != nil {
				return
			}
			batchErr = s.apply(ctx, r)
		})
		if batchErr != nil {
			// Do not commit: the batch is redelivered after the next poll.
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

// tag::apply[]
// apply turns one record into Redis writes. Only score_changed moves the
// board; the other event types are skipped but still committed.
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
	sc := ev.GetScoreChanged()
	if sc == nil {
		s.skipped.Add(1)
		return nil
	}
	if s.dedup {
		return s.applyOnce(ctx, r, ev, sc)
	}
	pipe := s.rdb.TxPipeline()
	pipe.ZIncrBy(ctx, globalKey, float64(sc.GetDelta()), ev.GetPlayerId())
	pipe.ZIncrBy(ctx, matchKey(ev.GetMatchId()), float64(sc.GetDelta()), ev.GetPlayerId())
	pipe.Expire(ctx, matchKey(ev.GetMatchId()), 24*time.Hour)
	if _, err := pipe.Exec(ctx); err != nil {
		return fmt.Errorf("redis: %w", err)
	}
	s.processed.Add(1)
	return nil
}

// end::apply[]

// tag::dedup[]
// applyOnce is the production shape of apply, enabled with LEADERBOARD_DEDUP=true.
// The partition and offset of a record are unique for the life of the topic,
// so a key processed:<partition>:<offset> set atomically alongside the
// increments turns at-least-once delivery into exactly-once effect: a replayed
// record finds its key and changes nothing.
var applyOnceScript = redis.NewScript(`
if redis.call('SET', KEYS[1], '1', 'NX', 'EX', ARGV[3]) == false then
  return 0
end
redis.call('ZINCRBY', KEYS[2], ARGV[1], ARGV[2])
redis.call('ZINCRBY', KEYS[3], ARGV[1], ARGV[2])
redis.call('EXPIRE', KEYS[3], ARGV[3])
return 1
`)

func (s *service) applyOnce(ctx context.Context, r *kgo.Record, ev *gamepb.GameEvent, sc *gamepb.ScoreChanged) error {
	processedKey := fmt.Sprintf("processed:%d:%d", r.Partition, r.Offset)
	n, err := applyOnceScript.Run(ctx, s.rdb,
		[]string{processedKey, globalKey, matchKey(ev.GetMatchId())},
		sc.GetDelta(), ev.GetPlayerId(), int64((24*time.Hour)/time.Second),
	).Int()
	if err != nil {
		return fmt.Errorf("redis: %w", err)
	}
	if n == 0 {
		s.dupes.Add(1)
		return nil
	}
	s.processed.Add(1)
	return nil
}

// end::dedup[]

func (s *service) watchLag(ctx context.Context) {
	t := time.NewTicker(time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
		lags, err := s.adm.Lag(ctx, s.group)
		if err != nil {
			s.lagErr.Store(err.Error())
			continue
		}
		l, ok := lags[s.group]
		if !ok || l.Error() != nil {
			continue
		}
		s.lag.Store(l.Lag.Total())
		s.members.Store(int64(len(l.Members)))
		s.lagErr.Store("")
	}
}

type entry struct {
	Rank   int     `json:"rank"`
	Player string  `json:"player_id"`
	Score  float64 `json:"score"`
}

func (s *service) top(ctx context.Context, match string, n int) ([]entry, error) {
	key := globalKey
	if match != "" {
		key = matchKey(match)
	}
	zs, err := s.rdb.ZRevRangeWithScores(ctx, key, 0, int64(n-1)).Result()
	if err != nil {
		return nil, err
	}
	out := make([]entry, 0, len(zs))
	for i, z := range zs {
		out = append(out, entry{Rank: i + 1, Player: fmt.Sprint(z.Member), Score: z.Score})
	}
	return out, nil
}

func (s *service) status(ctx context.Context) map[string]any {
	var parts []int32
	s.assigned.Range(func(k, _ any) bool { parts = append(parts, k.(int32)); return true })
	players, _ := s.rdb.ZCard(ctx, globalKey).Result()
	return map[string]any{
		"instance":           s.instance,
		"role":               s.role,
		"group":              s.group,
		"members":            s.members.Load(),
		"topic":              s.topic,
		"partitions":         parts,
		"lag":                s.lag.Load(),
		"lag_error":          s.lagErr.Load(),
		"processed":          s.processed.Load(),
		"skipped":            s.skipped.Load(),
		"poison_skipped":     s.poison.Load(),
		"duplicates_dropped": s.dupes.Load(),
		"dedup":              s.dedup,
		"players":            players,
		"updated_at":         time.Now().UTC().Format(time.RFC3339),
	}
}

// tag::http[]
func (s *service) serve(addr string) {
	mux := http.NewServeMux()
	sub, err := fs.Sub(static, "static")
	if err != nil {
		log.Fatal(err)
	}
	mux.Handle("/", http.FileServer(http.FS(sub)))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if err := s.rdb.Ping(r.Context()).Err(); err != nil {
			http.Error(w, err.Error(), http.StatusServiceUnavailable)
			return
		}
		writeJSON(w, map[string]any{"status": "ok", "instance": s.instance, "group": s.group})
	})
	mux.HandleFunc("/api/top", func(w http.ResponseWriter, r *http.Request) {
		n, _ := strconv.Atoi(r.URL.Query().Get("n"))
		if n <= 0 || n > 100 {
			n = 10
		}
		top, err := s.top(r.Context(), r.URL.Query().Get("match"), n)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, map[string]any{"match": r.URL.Query().Get("match"), "top": top, "status": s.status(r.Context())})
	})
	// Server-sent events: one snapshot every 500 ms, no polling from the page.
	mux.HandleFunc("/events", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "streaming unsupported", http.StatusInternalServerError)
			return
		}
		t := time.NewTicker(500 * time.Millisecond)
		defer t.Stop()
		for {
			top, err := s.top(r.Context(), "", 10)
			if err == nil {
				b, _ := json.Marshal(map[string]any{"top": top, "status": s.status(r.Context())})
				fmt.Fprintf(w, "data: %s\n\n", b)
				flusher.Flush()
			}
			select {
			case <-r.Context().Done():
				return
			case <-t.C:
			}
		}
	})
	log.Printf("dashboard on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("http: %v", err)
	}
}

// end::http[]

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}
