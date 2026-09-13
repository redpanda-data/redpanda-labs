// Package schema wires the Protobuf types in game_events.proto to Schema
// Registry.
//
// Producers look a schema up, they never register one: the contract is
// created by `make schemas` (step 3) and the services refuse to write until
// it exists. Consumers learn every version of a subject so a record written
// under any registered schema ID decodes, and treat an unknown ID as poison.
package schema

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/twmb/franz-go/pkg/sr"
	"google.golang.org/protobuf/proto"

	"multiplayer-gaming/services/internal/gamepb"
)

// ErrUnknownSchema is returned by Decode when the record's schema ID is not
// registered under the subject the consumer reads. The record is poison for
// this consumer: log it, count it, and move on.
var ErrUnknownSchema = errors.New("record carries a schema id that is not registered under this subject")

// Subject is the Schema Registry subject for a topic's values.
func Subject(topic string) string { return topic + "-value" }

// ReadFile returns the schema text the service is compiled against. The same
// file is what step 3 registers with rpk, so the lookup below matches exactly.
func ReadFile(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read schema file %s: %w", path, err)
	}
	return string(b), nil
}

// tag::lookup[]
// WaitForSchema polls Schema Registry until the exact schema text is
// registered under subject and returns its ID. It never registers the schema:
// the producer uses the contract, the contract is created by `make schemas`.
func WaitForSchema(ctx context.Context, cl *sr.Client, subject, schemaText string, onWait func()) (int, error) {
	s := sr.Schema{Schema: schemaText, Type: sr.TypeProtobuf}
	for {
		ss, err := cl.LookupSchema(ctx, subject, s)
		if err == nil {
			return ss.ID, nil
		}
		if ctx.Err() != nil {
			return 0, ctx.Err()
		}
		if onWait != nil {
			onWait()
		}
		select {
		case <-ctx.Done():
			return 0, ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}
}

// NewProducerSerde encodes one Protobuf message type in the Confluent wire
// format (magic byte, schema ID, Protobuf message index, payload) with one
// fixed schema ID. index is the message's position in the .proto file:
// GameEvent is 0, LeaderboardEntry is 8 (see IndexOf).
func NewProducerSerde(id int, prototype proto.Message, index int) *sr.Serde {
	var serde sr.Serde
	serde.Register(id, prototype,
		sr.Index(index),
		sr.EncodeFn(func(v any) ([]byte, error) { return proto.Marshal(v.(proto.Message)) }),
		sr.DecodeFn(func(b []byte, v any) error { return proto.Unmarshal(b, v.(proto.Message)) }),
	)
	return &serde
}

// IndexOf is the position of a top-level message in game_events.proto. The
// wire format carries it so a reader knows which message in the file a record
// is; rpk and Console read it too.
func IndexOf(m proto.Message) int {
	switch m.(type) {
	case *gamepb.GameEvent:
		return 0
	case *gamepb.LeaderboardEntry:
		return 8
	}
	panic(fmt.Sprintf("schema: no message index for %T", m))
}

// end::lookup[]

// tag::decoder[]
// Decoder decodes the records of one subject into one Protobuf message type.
// It knows every version registered under the subject and refreshes that list
// once when it meets a schema ID it has not seen, so a schema evolved while
// the consumer runs still decodes and a bogus ID is reported as
// ErrUnknownSchema.
type Decoder struct {
	cl        *sr.Client
	subject   string
	prototype proto.Message
	serde     sr.Serde
	known     map[int]struct{}
}

// NewDecoder decodes GameEvent records (game.player-events, game.match-events,
// game.achievements).
func NewDecoder(ctx context.Context, cl *sr.Client, subject string) (*Decoder, error) {
	return NewMessageDecoder(ctx, cl, subject, &gamepb.GameEvent{})
}

// NewMessageDecoder decodes records of any message in game_events.proto, for
// example LeaderboardEntry on game.leaderboard.
func NewMessageDecoder(ctx context.Context, cl *sr.Client, subject string, prototype proto.Message) (*Decoder, error) {
	d := &Decoder{cl: cl, subject: subject, prototype: prototype, known: map[int]struct{}{}}
	if err := d.refresh(ctx); err != nil {
		return nil, err
	}
	return d, nil
}

func (d *Decoder) refresh(ctx context.Context) error {
	versions, err := d.cl.SubjectVersions(ctx, d.subject)
	if err != nil {
		return fmt.Errorf("list versions of %s: %w", d.subject, err)
	}
	for _, v := range versions {
		ss, err := d.cl.SchemaByVersion(ctx, d.subject, v)
		if err != nil {
			return fmt.Errorf("fetch %s version %d: %w", d.subject, v, err)
		}
		if _, ok := d.known[ss.ID]; ok {
			continue
		}
		d.known[ss.ID] = struct{}{}
		d.serde.Register(ss.ID, d.prototype,
			sr.Index(IndexOf(d.prototype)),
			sr.DecodeFn(func(b []byte, v any) error { return proto.Unmarshal(b, v.(proto.Message)) }),
		)
	}
	return nil
}

// Known reports how many schema IDs decode under this subject.
func (d *Decoder) Known() int { return len(d.known) }

// Decode returns the event or ErrUnknownSchema.
func (d *Decoder) Decode(ctx context.Context, value []byte) (*gamepb.GameEvent, error) {
	var ev gamepb.GameEvent
	if err := d.DecodeInto(ctx, value, &ev); err != nil {
		return nil, err
	}
	return &ev, nil
}

// DecodeInto fills msg, which must be the decoder's message type, or returns
// ErrUnknownSchema.
func (d *Decoder) DecodeInto(ctx context.Context, value []byte, msg proto.Message) error {
	id, _, err := d.serde.DecodeID(value)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrUnknownSchema, err)
	}
	if _, ok := d.known[id]; !ok {
		if err := d.refresh(ctx); err != nil {
			log.Printf("schema refresh failed: %v", err)
		}
		if _, ok := d.known[id]; !ok {
			return fmt.Errorf("%w (id %d)", ErrUnknownSchema, id)
		}
	}
	if err := d.serde.Decode(value, msg); err != nil {
		return fmt.Errorf("decode with schema %d: %w", id, err)
	}
	return nil
}

// end::decoder[]

// WaitForRegistry blocks until Schema Registry answers.
func WaitForRegistry(ctx context.Context, cl *sr.Client) error {
	for {
		if _, err := cl.Subjects(ctx); err == nil {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}
}
