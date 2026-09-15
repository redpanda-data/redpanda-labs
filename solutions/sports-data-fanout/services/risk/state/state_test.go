package state

import (
	"testing"

	"sports-data-fanout/services/internal/feed"
)

func ev(seq int64, typ, market string) feed.Event {
	return feed.Event{FixtureID: "fx-1", Seq: seq, EventType: typ, MarketID: market, FeedTS: seq * 1000}
}

func TestSuspendAndResumeMoveAMarketBetweenTheCounts(t *testing.T) {
	b := New()
	b.Apply(ev(1, feed.TypeMarketUpdate, "fx-1:match-odds"))
	got := b.Apply(ev(2, feed.TypeMarketUpdate, "fx-1:totals"))
	if got.OpenMarkets != 2 || got.SuspendedMarkets != 0 {
		t.Fatalf("after two updates: open=%d suspended=%d, want 2/0", got.OpenMarkets, got.SuspendedMarkets)
	}
	got = b.Apply(ev(3, feed.TypeMarketSuspend, "fx-1:totals"))
	if got.OpenMarkets != 1 || got.SuspendedMarkets != 1 {
		t.Fatalf("after suspend: open=%d suspended=%d, want 1/1", got.OpenMarkets, got.SuspendedMarkets)
	}
	got = b.Apply(ev(4, feed.TypeMarketResume, "fx-1:totals"))
	if got.OpenMarkets != 2 || got.SuspendedMarkets != 0 {
		t.Fatalf("after resume: open=%d suspended=%d, want 2/0", got.OpenMarkets, got.SuspendedMarkets)
	}
}

func TestMatchEndClosesEveryMarket(t *testing.T) {
	b := New()
	b.Apply(ev(1, feed.TypeMarketUpdate, "fx-1:match-odds"))
	b.Apply(ev(2, feed.TypeMarketUpdate, "fx-1:totals"))
	got := b.Apply(ev(3, feed.TypeMatchEnd, ""))
	if got.OpenMarkets != 0 || got.SuspendedMarkets != 2 || !got.Settled {
		t.Fatalf("after match end: open=%d suspended=%d settled=%v, want 0/2/true",
			got.OpenMarkets, got.SuspendedMarkets, got.Settled)
	}
}

func TestAGapInTheProviderSequenceIsCountedNotFilled(t *testing.T) {
	b := New()
	b.Apply(ev(1, feed.TypeMarketUpdate, "fx-1:match-odds"))
	got := b.Apply(ev(4, feed.TypeMarketUpdate, "fx-1:match-odds"))
	if got.Gaps != 2 {
		t.Fatalf("gaps = %d, want 2 (sequences 2 and 3 never arrived)", got.Gaps)
	}
	if got.LastSeq != 4 {
		t.Fatalf("last seq = %d, want 4", got.LastSeq)
	}
	// A contiguous event adds no gap, so the counter is not just "jumps seen".
	if got = b.Apply(ev(5, feed.TypeMarketUpdate, "fx-1:match-odds")); got.Gaps != 2 {
		t.Fatalf("gaps = %d after a contiguous event, want 2", got.Gaps)
	}
}

// A replay redelivers records the consumer has already folded in. The state
// must come out the same, or the compacted topic disagrees with the log.
func TestReplayingTheSameEventsIsIdempotent(t *testing.T) {
	events := []feed.Event{
		ev(1, feed.TypeMarketUpdate, "fx-1:match-odds"),
		ev(2, feed.TypeMarketSuspend, "fx-1:match-odds"),
		ev(3, feed.TypeMarketResume, "fx-1:match-odds"),
		ev(4, feed.TypeMatchEnd, ""),
	}
	first := New()
	for _, e := range events {
		first.Apply(e)
	}
	again := New()
	for range 2 {
		for _, e := range events {
			again.Apply(e)
		}
	}
	if first.Totals() != again.Totals() {
		t.Fatalf("totals after replay = %+v, want %+v", again.Totals(), first.Totals())
	}
}

func TestSnapshotsDoNotShareTheInternalMarketMap(t *testing.T) {
	b := New()
	snap := b.Apply(ev(1, feed.TypeMarketUpdate, "fx-1:match-odds"))
	if snap.markets != nil {
		t.Fatal("snapshot carries the internal map, so a caller can mutate the book")
	}
}
