package sim

import (
	"reflect"
	"testing"

	"sports-data-fanout/services/internal/feed"
	"sports-data-fanout/services/odds/pricing"
)

func fixtures() []Fixture {
	return []Fixture{
		{ID: "fx-2", Home: "B", Away: "C", League: "EPL", Markets: []string{"match-odds", "totals"}},
		{ID: "fx-1", Home: "A", Away: "D", League: "EPL", Markets: []string{"match-odds"}},
	}
}

func drain(t *testing.T, cfg Config) []feed.Event {
	t.Helper()
	g, err := New(cfg)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	var out []feed.Event
	for i := range 10000 {
		ev, ok := g.Next(int64(1757000000000 + i))
		if !ok {
			break
		}
		out = append(out, ev)
	}
	return out
}

func TestTheSameSeedGivesTheSameFeed(t *testing.T) {
	a := drain(t, Config{Seed: 42, Fixtures: fixtures(), SuspendEvery: 7})
	b := drain(t, Config{Seed: 42, Fixtures: fixtures(), SuspendEvery: 7})
	if len(a) != len(b) || len(a) == 0 {
		t.Fatalf("lengths %d and %d", len(a), len(b))
	}
	for i := range a {
		if !reflect.DeepEqual(a[i], b[i]) {
			t.Fatalf("event %d differs:\n %+v\n %+v", i, a[i], b[i])
		}
	}
	// A different seed must actually change the feed, or the expected output in
	// the docs would be seed-independent by accident.
	c := drain(t, Config{Seed: 43, Fixtures: fixtures(), SuspendEvery: 7})
	same := len(c) == len(a)
	if same {
		for i := range a {
			if !reflect.DeepEqual(a[i], c[i]) {
				same = false
				break
			}
		}
	}
	if same {
		t.Fatal("seed 43 produced the same feed as seed 42")
	}
}

func TestSequenceNumbersAreContiguousPerFixtureWithoutDrops(t *testing.T) {
	events := drain(t, Config{Seed: 42, Fixtures: fixtures(), SuspendEvery: 7})
	last := map[string]int64{}
	for _, ev := range events {
		if want := last[ev.FixtureID] + 1; ev.Seq != want {
			t.Fatalf("fixture %s: seq %d, want %d", ev.FixtureID, ev.Seq, want)
		}
		last[ev.FixtureID] = ev.Seq
	}
	if len(last) != 2 {
		t.Fatalf("saw %d fixtures, want 2", len(last))
	}
}

func TestDropEveryLeavesGapsInTheSequence(t *testing.T) {
	events := drain(t, Config{Seed: 42, Fixtures: fixtures(), SuspendEvery: 7, DropEvery: 5})
	gaps := 0
	last := map[string]int64{}
	for _, ev := range events {
		if prev, seen := last[ev.FixtureID]; seen && ev.Seq > prev+1 {
			gaps += int(ev.Seq - prev - 1)
		}
		last[ev.FixtureID] = ev.Seq
	}
	if gaps == 0 {
		t.Fatal("DropEvery 5 produced no sequence gaps")
	}
}

func TestEventsPerFixtureSetsTheLengthOfAMatch(t *testing.T) {
	events := drain(t, Config{Seed: 42, Fixtures: fixtures(), EventsPerFixture: 30})
	if len(events) != 60 {
		t.Fatalf("%d events for two fixtures of 30, want 60", len(events))
	}
}

func TestEveryFixtureEndsAndTheFeedStops(t *testing.T) {
	events := drain(t, Config{Seed: 42, Fixtures: fixtures()})
	ended := map[string]bool{}
	for _, ev := range events {
		if ev.EventType == feed.TypeMatchEnd {
			ended[ev.FixtureID] = true
		}
	}
	if len(ended) != 2 {
		t.Fatalf("%d fixtures ended, want 2", len(ended))
	}
	// Two fixtures at the default length, so the feed stops at a knowable
	// number rather than whenever it feels like it.
	if len(events) != 2*250 {
		t.Fatalf("%d events for two fixtures, want %d", len(events), 2*250)
	}
}

func TestProbabilitiesStayInRangeAfterGoals(t *testing.T) {
	for _, ev := range drain(t, Config{Seed: 7, Fixtures: fixtures()}) {
		if ev.EventType != feed.TypeMarketUpdate {
			continue
		}
		if ev.Probability <= 0 || ev.Probability >= 1 {
			t.Fatalf("probability %v is not a probability (event %+v)", ev.Probability, ev)
		}
	}
}

// The contract between the two halves of this solution: every probability the
// feed emits must be one the odds engine can turn into a price. Without this
// test the generator can drift into values that price below the 1.01 floor,
// and the only symptom is a rejection counter nobody looks at.
func TestEveryGeneratedProbabilityCanBePriced(t *testing.T) {
	// A long run, so the post-goal drift has time to reach its bounds.
	events := drain(t, Config{Seed: 42, Fixtures: fixtures(), SuspendEvery: 11, EventsPerFixture: 2000})
	updates := 0
	for _, ev := range events {
		if ev.EventType != feed.TypeMarketUpdate {
			continue
		}
		updates++
		if _, err := pricing.Price(ev, false); err != nil {
			t.Fatalf("event %+v cannot be priced: %v", ev, err)
		}
	}
	if updates < 1000 {
		t.Fatalf("only %d market updates in the run; the test is not exercising the drift", updates)
	}
}
