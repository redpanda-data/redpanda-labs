package sim

import (
	"testing"
	"time"

	"google.golang.org/protobuf/proto"
)

func TestSameSeedSameEvents(t *testing.T) {
	a := New(Config{Seed: 42, Players: 12, Region: "eu-west"})
	b := New(Config{Seed: 42, Players: 12, Region: "eu-west"})
	for i := 0; i < 5000; i++ {
		ea, eb := a.Next(), b.Next()
		if !proto.Equal(ea, eb) {
			t.Fatalf("event %d differs:\n%v\n%v", i, ea, eb)
		}
	}
}

func TestDifferentSeedDifferentEvents(t *testing.T) {
	a := New(Config{Seed: 1, Players: 12})
	b := New(Config{Seed: 2, Players: 12})
	same := 0
	for i := 0; i < 500; i++ {
		if proto.Equal(a.Next(), b.Next()) {
			same++
		}
	}
	if same == 500 {
		t.Fatal("two seeds produced identical streams")
	}
}

func TestNextReturnsExactlyOneEventAndCountsIt(t *testing.T) {
	g := New(Config{Seed: 7, Players: 8})
	const n = 1234
	for i := 0; i < n; i++ {
		if g.Next() == nil {
			t.Fatal("nil event")
		}
	}
	var total int64
	for _, c := range g.Counts() {
		total += c
	}
	if total != n {
		t.Fatalf("counted %d events, want %d", total, n)
	}
}

func TestMatchLifecycleIsConsistent(t *testing.T) {
	g := New(Config{Seed: 3, Players: 8, MatchDuration: 10 * time.Second})
	open := map[string]int{} // match id -> players joined
	left := map[string]int{}
	ended := 0
	for i := 0; i < 3000; i++ {
		ev := g.Next()
		switch EventType(ev) {
		case "match_started":
			if Topic(ev) != TopicMatchEvents || Key(ev) != ev.GetMatchId() {
				t.Fatalf("match_started routed to %s key %q", Topic(ev), Key(ev))
			}
			open[ev.GetMatchId()] = len(ev.GetMatchStarted().GetPlayerIds())
		case "player_joined", "score_changed", "item_acquired", "player_left":
			if Topic(ev) != TopicPlayerEvents || Key(ev) != ev.GetPlayerId() || ev.GetPlayerId() == "" {
				t.Fatalf("%s routed to %s key %q", EventType(ev), Topic(ev), Key(ev))
			}
			if EventType(ev) == "player_left" {
				left[ev.GetMatchId()]++
			}
		case "match_ended":
			ended++
			me := ev.GetMatchEnded()
			if left[ev.GetMatchId()] != len(me.GetPlayerIds()) {
				t.Fatalf("match %s ended with %d player_left events for %d players", ev.GetMatchId(), left[ev.GetMatchId()], len(me.GetPlayerIds()))
			}
			found := false
			for _, p := range me.GetPlayerIds() {
				if p == me.GetWinnerPlayerId() {
					found = true
				}
			}
			if !found {
				t.Fatalf("winner %s not among participants", me.GetWinnerPlayerId())
			}
		}
	}
	if ended == 0 {
		t.Fatal("no match ended in 3000 events")
	}
}

func TestSimulatedClockAdvances(t *testing.T) {
	g := New(Config{Seed: 1, Players: 4, Tick: time.Second})
	first := g.Next().GetOccurredAt().AsTime()
	var last time.Time
	for i := 0; i < 99; i++ {
		last = g.Next().GetOccurredAt().AsTime()
	}
	if !last.After(first) {
		t.Fatalf("clock did not advance: %v -> %v", first, last)
	}
}
