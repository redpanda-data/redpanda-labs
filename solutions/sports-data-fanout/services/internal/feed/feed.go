// Package feed is the shared contract between the producer and the two Go
// consumers: the Avro schemas, the Schema Registry lookups, and the Go types
// the events decode into.
//
// Two rules the services never break:
//
//   - Nobody registers a schema. `make schemas` creates the contract and the
//     services wait for it. A producer that registers its own schema silently
//     becomes the source of truth for a shape nobody reviewed.
//   - Records are decoded with the WRITER's schema, fetched by the ID in the
//     record, never with whatever the consumer was built against. That is what
//     makes it safe for the topic to hold v1 and v2 records at the same time.
package feed

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/hamba/avro/v2"
	"github.com/twmb/franz-go/pkg/sr"
)

// Event is the decoded form of one provider event. Fields the writer's schema
// does not carry keep their zero value, which is why a v1 record read by this
// code has Provider "".
type Event struct {
	FeedTS      int64
	Seq         int64
	FixtureID   string
	EventType   string
	MarketID    string
	Selection   string
	Probability float64
	Extra       map[string]string
	Provider    string

	// WriterSchemaID is the ID the record carried, kept so a consumer can
	// report which version it is seeing without guessing.
	WriterSchemaID int
}

// Event type symbols, matching the enum in feed_event.avsc.
const (
	TypeScore         = "SCORE"
	TypeMarketUpdate  = "MARKET_UPDATE"
	TypeMarketSuspend = "MARKET_SUSPEND"
	TypeMarketResume  = "MARKET_RESUME"
	TypeInjury        = "INJURY"
	TypeMatchEnd      = "MATCH_END"
)

// ErrUnknownSchema means the record's schema ID is not registered under the
// subject this consumer reads: poison for this consumer. Count it and move on
// rather than stopping the group, because one bad record must not stall a
// feed that every downstream service depends on.
var ErrUnknownSchema = errors.New("record carries a schema id that is not registered under this subject")

// ReadFile returns a schema file's text. The same file is what `make schemas`
// registers, so a lookup of this exact text matches.
func ReadFile(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read schema file %s: %w", path, err)
	}
	return string(b), nil
}

// tag::lookup[]
// WaitForSchema polls the registry until schemaText is registered under
// subject and returns its ID. It never registers anything.
func WaitForSchema(ctx context.Context, cl *sr.Client, subject, schemaText string, onWait func()) (int, error) {
	want := sr.Schema{Schema: schemaText, Type: sr.TypeAvro}
	for {
		ss, err := cl.LookupSchema(ctx, subject, want)
		if err == nil {
			return ss.ID, nil
		}
		if onWait != nil {
			onWait()
		}
		select {
		case <-ctx.Done():
			return 0, fmt.Errorf("waiting for subject %s: %w", subject, ctx.Err())
		case <-time.After(2 * time.Second):
		}
	}
}

// end::lookup[]

// tag::registry[]
// Registry decodes values written under any version of one subject. It fetches
// a schema the first time it sees its ID and caches the parsed codec, so the
// steady state costs no registry calls.
type Registry struct {
	cl      *sr.Client
	subject string

	mu    sync.RWMutex
	codec map[int]avro.Schema
	known map[int]bool // false means: asked the registry, and it is not ours
}

// NewRegistry returns a decoder for one subject.
func NewRegistry(cl *sr.Client, subject string) *Registry {
	return &Registry{cl: cl, subject: subject, codec: map[int]avro.Schema{}, known: map[int]bool{}}
}

// Schema returns the parsed writer schema for an ID, or ErrUnknownSchema when
// that ID is not one of this subject's versions.
func (r *Registry) Schema(ctx context.Context, id int) (avro.Schema, error) {
	r.mu.RLock()
	codec, ok := r.codec[id]
	known, asked := r.known[id]
	r.mu.RUnlock()
	if ok {
		return codec, nil
	}
	if asked && !known {
		return nil, fmt.Errorf("%w: id %d, subject %s", ErrUnknownSchema, id, r.subject)
	}

	// Ask for the subject's versions rather than the ID on its own: an ID that
	// exists in the registry but under a different subject is still poison
	// here, and a shared cluster has plenty of those.
	ids, err := r.subjectIDs(ctx)
	if err != nil {
		return nil, err
	}
	if !ids[id] {
		r.mu.Lock()
		r.known[id] = false
		r.mu.Unlock()
		return nil, fmt.Errorf("%w: id %d, subject %s", ErrUnknownSchema, id, r.subject)
	}

	s, err := r.cl.SchemaByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("fetch schema %d: %w", id, err)
	}
	parsed, err := avro.Parse(s.Schema)
	if err != nil {
		return nil, fmt.Errorf("parse schema %d: %w", id, err)
	}
	r.mu.Lock()
	r.codec[id] = parsed
	r.known[id] = true
	r.mu.Unlock()
	return parsed, nil
}

func (r *Registry) subjectIDs(ctx context.Context) (map[int]bool, error) {
	versions, err := r.cl.SubjectVersions(ctx, r.subject)
	if err != nil {
		return nil, fmt.Errorf("list versions of %s: %w", r.subject, err)
	}
	out := make(map[int]bool, len(versions))
	for _, v := range versions {
		s, err := r.cl.SchemaByVersion(ctx, r.subject, v)
		if err != nil {
			return nil, fmt.Errorf("fetch %s version %d: %w", r.subject, v, err)
		}
		out[s.ID] = true
	}
	return out, nil
}

// end::registry[]

// tag::decode[]
// Decode turns one record value into an Event using the writer's schema.
//
// The Avro body is decoded into a map first, then read field by field. A
// provider feed is exactly the case where that pays: a field the consumer has
// never heard of is carried in Extra instead of breaking the decode, and a
// field the writer's version does not have is simply absent.
func Decode(sch avro.Schema, schemaID int, body []byte) (Event, error) {
	var raw map[string]any
	if err := avro.Unmarshal(sch, body, &raw); err != nil {
		return Event{}, fmt.Errorf("decode avro body: %w", err)
	}
	ev := Event{
		FeedTS:         asInt64(raw["feed_ts"]),
		Seq:            asInt64(raw["seq"]),
		FixtureID:      asString(raw["fixture_id"]),
		EventType:      asString(raw["event_type"]),
		MarketID:       asString(raw["market_id"]),
		Selection:      asString(raw["selection"]),
		Probability:    asFloat(raw["probability"]),
		Extra:          asStringMap(raw["extra"]),
		Provider:       asString(raw["provider"]),
		WriterSchemaID: schemaID,
	}
	if ev.FixtureID == "" {
		return Event{}, errors.New("event has no fixture_id")
	}
	return ev, nil
}

// end::decode[]

// Encode writes an event under one schema. Only the feed service uses it.
func Encode(sch avro.Schema, ev Event, withProvider bool) ([]byte, error) {
	rec := map[string]any{
		"feed_ts":     ev.FeedTS,
		"seq":         ev.Seq,
		"fixture_id":  ev.FixtureID,
		"event_type":  ev.EventType,
		"market_id":   ev.MarketID,
		"selection":   ev.Selection,
		"probability": ev.Probability,
		"extra":       toAnyMap(ev.Extra),
	}
	if withProvider {
		rec["provider"] = ev.Provider
	}
	b, err := avro.Marshal(sch, rec)
	if err != nil {
		return nil, fmt.Errorf("encode avro body: %w", err)
	}
	return b, nil
}

// MarshalJSON-ish helpers for the HTTP endpoints, so the services do not each
// invent a shape.
func JSON(v any) []byte {
	b, err := json.Marshal(v)
	if err != nil {
		return []byte(`{"error":"marshal"}`)
	}
	return b
}

func asInt64(v any) int64 {
	switch n := v.(type) {
	case int64:
		return n
	case int32:
		return int64(n)
	case int:
		return int64(n)
	case float64:
		return int64(n)
	case time.Time:
		return n.UnixMilli()
	}
	return 0
}

func asFloat(v any) float64 {
	switch n := v.(type) {
	case float64:
		return n
	case float32:
		return float64(n)
	case int64:
		return float64(n)
	}
	return 0
}

func asString(v any) string {
	switch s := v.(type) {
	case string:
		return s
	case []byte:
		return string(s)
	}
	return ""
}

func asStringMap(v any) map[string]string {
	m, ok := v.(map[string]any)
	if !ok {
		return nil
	}
	out := make(map[string]string, len(m))
	for k, val := range m {
		out[k] = asString(val)
	}
	return out
}

func toAnyMap(m map[string]string) map[string]any {
	out := make(map[string]any, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}
