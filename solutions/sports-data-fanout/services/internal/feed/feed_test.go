package feed

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/hamba/avro/v2"
)

// The schema files are the contract, so the tests read the real ones rather
// than a copy that can drift.
func schema(t *testing.T, rel string) avro.Schema {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", "..", "..", "schemas", rel))
	if err != nil {
		t.Fatalf("read %s: %v", rel, err)
	}
	s, err := avro.Parse(string(b))
	if err != nil {
		t.Fatalf("parse %s: %v", rel, err)
	}
	return s
}

func sample() Event {
	return Event{
		FeedTS:      1757000000000,
		Seq:         7,
		FixtureID:   "fx-epl-2026-0412",
		EventType:   TypeMarketUpdate,
		MarketID:    "fx-epl-2026-0412:match-odds",
		Selection:   "home",
		Probability: 0.4512,
		Extra:       map[string]string{"league": "EPL"},
		Provider:    "sportradar",
	}
}

func TestRoundTripUnderV1(t *testing.T) {
	v1 := schema(t, "feed_event.avsc")
	body, err := Encode(v1, sample(), false)
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	got, err := Decode(v1, 11, body)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	want := sample()
	want.Provider = "" // v1 has no provider field at all
	want.WriterSchemaID = 11
	if got.FeedTS != want.FeedTS || got.Seq != want.Seq || got.FixtureID != want.FixtureID ||
		got.EventType != want.EventType || got.MarketID != want.MarketID ||
		got.Selection != want.Selection || got.Probability != want.Probability {
		t.Fatalf("round trip lost fields:\n got %+v\nwant %+v", got, want)
	}
	if got.Extra["league"] != "EPL" {
		t.Fatalf("extra = %v, want league EPL", got.Extra)
	}
	if got.Provider != "" {
		t.Fatalf("provider = %q, want empty: v1 does not carry it", got.Provider)
	}
	if got.WriterSchemaID != 11 {
		t.Fatalf("writer schema id = %d, want 11", got.WriterSchemaID)
	}
}

// The reason the consumers decode with the writer's schema: both versions are
// in the topic at once, and each decodes correctly on its own terms.
func TestBothVersionsDecodeFromTheirOwnSchema(t *testing.T) {
	v1 := schema(t, "feed_event.avsc")
	v2 := schema(t, filepath.Join("history", "feed_event.v2.avsc"))

	oldBody, err := Encode(v1, sample(), false)
	if err != nil {
		t.Fatalf("encode v1: %v", err)
	}
	newBody, err := Encode(v2, sample(), true)
	if err != nil {
		t.Fatalf("encode v2: %v", err)
	}

	fromV1, err := Decode(v1, 1, oldBody)
	if err != nil {
		t.Fatalf("decode v1: %v", err)
	}
	fromV2, err := Decode(v2, 2, newBody)
	if err != nil {
		t.Fatalf("decode v2: %v", err)
	}
	if fromV1.Provider != "" || fromV2.Provider != "sportradar" {
		t.Fatalf("provider: v1=%q v2=%q, want \"\" and sportradar", fromV1.Provider, fromV2.Provider)
	}
	// Everything a consumer relies on is identical across the versions, which
	// is what "backward compatible" has to mean in practice.
	if fromV1.Seq != fromV2.Seq || fromV1.Probability != fromV2.Probability || fromV1.FixtureID != fromV2.FixtureID {
		t.Fatalf("the shared fields differ between versions:\n v1 %+v\n v2 %+v", fromV1, fromV2)
	}

	// Negative control: the v2 body is longer, so the two really are different
	// encodings rather than the same bytes passing twice.
	if len(newBody) <= len(oldBody) {
		t.Fatalf("v2 body (%d bytes) should be longer than v1 (%d)", len(newBody), len(oldBody))
	}
}

func TestDecodeRejectsAnEventWithNoFixture(t *testing.T) {
	v1 := schema(t, "feed_event.avsc")
	ev := sample()
	ev.FixtureID = ""
	body, err := Encode(v1, ev, false)
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	if _, err := Decode(v1, 1, body); err == nil {
		t.Fatal("decoded an event with no fixture_id; it has no key and cannot be ordered")
	}
}
