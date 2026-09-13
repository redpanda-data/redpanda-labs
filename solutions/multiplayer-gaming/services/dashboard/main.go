// The leaderboard dashboard is a thin reader of the compacted topic
// game.leaderboard. It consumes the topic from the first record with no
// consumer group, keeps one entry per player in a map, and serves the top 10
// over HTTP and server-sent events. It never reads game.player-events and
// never computes a score: the leaderboard service did that and published the
// result. Because it joins no group, scaling the service to three members
// does not move the dashboard, and restarting the dashboard costs one read of
// a small compacted topic.
package main

import (
	"context"
	"embed"
	"encoding/json"
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

	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"

	"multiplayer-gaming/services/internal/board"
	"multiplayer-gaming/services/internal/envvar"
	"multiplayer-gaming/services/internal/gamepb"
)

//go:embed static/index.html
var static embed.FS

type dashboard struct {
	reader   *board.Reader
	topic    string
	group    string
	instance string

	mu       sync.Mutex
	entries  map[string]*gamepb.LeaderboardEntry
	caughtUp bool
	records  int64

	tombstones atomic.Int64
	lag        atomic.Int64
	members    atomic.Int64
	lagErr     atomic.Value
	ready      atomic.Bool
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	brokers := envvar.List("KAFKA_BROKERS", "redpanda:9092")
	srURL := envvar.String("SCHEMA_REGISTRY_URL", "http://redpanda:8081")
	host, _ := os.Hostname()
	d := &dashboard{
		topic:    envvar.String("TOPIC", board.Topic),
		group:    envvar.String("GROUP", "leaderboard"),
		instance: host,
		entries:  map[string]*gamepb.LeaderboardEntry{},
	}
	d.lagErr.Store("")
	go d.serve(envvar.String("HTTP_ADDR", ":8080"))

	// The group's lag and member count come from the admin API, not from
	// membership: the dashboard watches the consumers, it is not one of them.
	adminCl, err := kgo.NewClient(kgo.SeedBrokers(brokers...), kgo.ClientID("leaderboard-dashboard-admin"))
	if err != nil {
		log.Fatalf("kafka client: %v", err)
	}
	defer adminCl.Close()
	go d.watchLag(ctx, kadm.NewClient(adminCl))

	// tag::read[]
	// Open waits for the subject and the topic (both created by the reader in
	// steps 2 and 3), then reads from the start of every partition. The map
	// holds the latest entry per key, which is exactly what compaction leaves
	// on the topic; the dashboard just gets there first.
	d.reader, err = board.Open(ctx, brokers, srURL, d.topic, "leaderboard-dashboard-"+host)
	if err != nil {
		if ctx.Err() != nil {
			return
		}
		log.Fatal(err)
	}
	defer d.reader.Close()
	d.ready.Store(true)
	go d.watchEnd(ctx)

	for ctx.Err() == nil {
		err := d.reader.Poll(ctx, func(key string, e *gamepb.LeaderboardEntry, _ *kgo.Record) {
			d.mu.Lock()
			defer d.mu.Unlock()
			if e == nil {
				delete(d.entries, key)
				d.tombstones.Add(1)
				return
			}
			d.entries[key] = e
		})
		if err != nil && ctx.Err() == nil {
			log.Printf("poll: %v", err)
			time.Sleep(time.Second)
		}
	}
	// end::read[]
}

// watchEnd compares the reader's position with the topic's high watermarks
// once a second, so the page can say whether it has read everything.
func (d *dashboard) watchEnd(ctx context.Context) {
	t := time.NewTicker(time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
		ends, err := d.reader.EndOffsets(ctx)
		if err != nil {
			continue
		}
		d.mu.Lock()
		d.caughtUp = d.reader.CaughtUp(ends)
		d.records = d.reader.Records()
		d.mu.Unlock()
	}
}

func (d *dashboard) watchLag(ctx context.Context, adm *kadm.Client) {
	t := time.NewTicker(time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
		lags, err := adm.Lag(ctx, d.group)
		if err != nil {
			d.lagErr.Store(err.Error())
			continue
		}
		l, ok := lags[d.group]
		if !ok || l.Error() != nil {
			continue
		}
		d.lag.Store(l.Lag.Total())
		d.members.Store(int64(len(l.Members)))
		d.lagErr.Store("")
	}
}

func (d *dashboard) top(n int) []board.Ranked {
	d.mu.Lock()
	defer d.mu.Unlock()
	return board.Top(d.entries, n)
}

func (d *dashboard) status() map[string]any {
	d.mu.Lock()
	players, caughtUp, records := len(d.entries), d.caughtUp, d.records
	d.mu.Unlock()
	return map[string]any{
		"instance":     d.instance,
		"topic":        d.topic,
		"ready":        d.ready.Load(),
		"players":      players,
		"records_read": records,
		"tombstones":   d.tombstones.Load(),
		"caught_up":    caughtUp,
		"group":        d.group,
		"members":      d.members.Load(),
		"lag":          d.lag.Load(),
		"lag_error":    d.lagErr.Load(),
		"updated_at":   time.Now().UTC().Format(time.RFC3339),
	}
}

// tag::http[]
func (d *dashboard) serve(addr string) {
	mux := http.NewServeMux()
	sub, err := fs.Sub(static, "static")
	if err != nil {
		log.Fatal(err)
	}
	mux.Handle("/", http.FileServer(http.FS(sub)))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]any{"status": "ok", "instance": d.instance, "ready": d.ready.Load()})
	})
	// The board only: stable output, so two snapshots of it can be compared
	// with diff. Volatile counters live under /api/status.
	mux.HandleFunc("/api/top", func(w http.ResponseWriter, r *http.Request) {
		n, _ := strconv.Atoi(r.URL.Query().Get("n"))
		if n <= 0 || n > 100 {
			n = 10
		}
		writeJSON(w, map[string]any{"top": d.top(n)})
	})
	mux.HandleFunc("/api/status", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, d.status())
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
			b, _ := json.Marshal(map[string]any{"top": d.top(10), "status": d.status()})
			fmt.Fprintf(w, "data: %s\n\n", b)
			flusher.Flush()
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
