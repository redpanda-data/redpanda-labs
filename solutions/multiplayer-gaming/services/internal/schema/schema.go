// Package schema wires the GameEvent Protobuf type to Schema Registry.
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

// NewProducerSerde encodes GameEvent values in the Confluent wire format
// (magic byte, schema ID, Protobuf message index, payload) with one fixed
// schema ID.
func NewProducerSerde(id int) *sr.Serde {
	var serde sr.Serde
	serde.Register(id, &gamepb.GameEvent{},
		sr.Index(0), // GameEvent is the first message in the file
		sr.EncodeFn(func(v any) ([]byte, error) { return proto.Marshal(v.(proto.Message)) }),
		sr.DecodeFn(func(b []byte, v any) error { return proto.Unmarshal(b, v.(proto.Message)) }),
	)
	return &serde
}

// end::lookup[]

// tag::decoder[]
// Decoder decodes GameEvent records for one subject. It knows every version
// registered under the subject and refreshes that list once when it meets a
// schema ID it has not seen, so a schema evolved while the consumer runs
// still decodes and a bogus ID is reported as ErrUnknownSchema.
type Decoder struct {
	cl      *sr.Client
	subject string
	serde   sr.Serde
	known   map[int]struct{}
}

func NewDecoder(ctx context.Context, cl *sr.Client, subject string) (*Decoder, error) {
	d := &Decoder{cl: cl, subject: subject, known: map[int]struct{}{}}
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
		d.serde.Register(ss.ID, &gamepb.GameEvent{},
			sr.Index(0),
			sr.DecodeFn(func(b []byte, v any) error { return proto.Unmarshal(b, v.(proto.Message)) }),
		)
	}
	return nil
}

// Known reports how many schema IDs decode under this subject.
func (d *Decoder) Known() int { return len(d.known) }

// Decode returns the event or ErrUnknownSchema.
func (d *Decoder) Decode(ctx context.Context, value []byte) (*gamepb.GameEvent, error) {
	id, _, err := d.serde.DecodeID(value)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrUnknownSchema, err)
	}
	if _, ok := d.known[id]; !ok {
		if err := d.refresh(ctx); err != nil {
			log.Printf("schema refresh failed: %v", err)
		}
		if _, ok := d.known[id]; !ok {
			return nil, fmt.Errorf("%w (id %d)", ErrUnknownSchema, id)
		}
	}
	var ev gamepb.GameEvent
	if err := d.serde.Decode(value, &ev); err != nil {
		return nil, fmt.Errorf("decode with schema %d: %w", id, err)
	}
	return &ev, nil
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
