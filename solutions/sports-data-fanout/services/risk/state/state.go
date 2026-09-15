// Package state keeps the trading desk's view of each fixture: how many
// markets are open, how many are suspended, and whether the provider's
// sequence has holes in it.
//
// It is a plain in-memory fold over the feed, which is the point: the state is
// derived from the log, so a replay rebuilds it exactly and no consumer has to
// be trusted to have kept it correctly.
package state

import (
	"sort"
	"sync"

	"sports-data-fanout/services/internal/feed"
)

// Fixture is the state of one match.
type Fixture struct {
	FixtureID        string `json:"fixture_id"`
	OpenMarkets      int    `json:"open_markets"`
	SuspendedMarkets int    `json:"suspended_markets"`
	LastEventType    string `json:"last_event_type"`
	LastSeq          int64  `json:"last_seq"`
	Gaps             int    `json:"gaps"`
	Settled          bool   `json:"settled"`
	UpdatedTS        int64  `json:"updated_ts"`

	// markets is the per-market suspension state the counts are derived from.
	markets map[string]bool
}

// Book is every fixture the consumer has seen.
type Book struct {
	mu       sync.RWMutex
	fixtures map[string]*Fixture
}

// New returns an empty book.
func New() *Book { return &Book{fixtures: map[string]*Fixture{}} }

// tag::apply[]
// Apply folds one event in and returns the fixture's new state.
//
// A gap is counted when the sequence jumps by more than one. It is never
// filled in and never treated as an error: the provider dropped an event, and
// the desk needs to know that a price may be stale, not to have the number
// quietly corrected.
func (b *Book) Apply(ev feed.Event) Fixture {
	b.mu.Lock()
	defer b.mu.Unlock()

	f := b.fixtures[ev.FixtureID]
	if f == nil {
		f = &Fixture{FixtureID: ev.FixtureID, markets: map[string]bool{}}
		b.fixtures[ev.FixtureID] = f
	}
	if f.LastSeq > 0 && ev.Seq > f.LastSeq+1 {
		f.Gaps += int(ev.Seq - f.LastSeq - 1)
	}
	if ev.Seq > f.LastSeq {
		f.LastSeq = ev.Seq
	}
	f.LastEventType = ev.EventType
	f.UpdatedTS = ev.FeedTS

	switch ev.EventType {
	case feed.TypeMarketUpdate, feed.TypeMarketResume:
		if ev.MarketID != "" {
			f.markets[ev.MarketID] = false
		}
	case feed.TypeMarketSuspend:
		if ev.MarketID != "" {
			f.markets[ev.MarketID] = true
		}
	case feed.TypeMatchEnd:
		// Settling closes every market: an open market on a finished fixture
		// is how a book takes a bet it cannot price.
		for id := range f.markets {
			f.markets[id] = true
		}
		f.Settled = true
	}

	f.OpenMarkets, f.SuspendedMarkets = 0, 0
	for _, suspended := range f.markets {
		if suspended {
			f.SuspendedMarkets++
		} else {
			f.OpenMarkets++
		}
	}
	return f.snapshot()
}

// end::apply[]

func (f *Fixture) snapshot() Fixture {
	out := *f
	out.markets = nil
	return out
}

// Get returns one fixture's state.
func (b *Book) Get(id string) (Fixture, bool) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	f, ok := b.fixtures[id]
	if !ok {
		return Fixture{}, false
	}
	return f.snapshot(), true
}

// All returns every fixture, ordered by id so the HTTP output is stable.
func (b *Book) All() []Fixture {
	b.mu.RLock()
	defer b.mu.RUnlock()
	out := make([]Fixture, 0, len(b.fixtures))
	for _, f := range b.fixtures {
		out = append(out, f.snapshot())
	}
	sort.Slice(out, func(i, j int) bool { return out[i].FixtureID < out[j].FixtureID })
	return out
}

// Totals is the one-line summary the /healthz and verify checks read.
type Totals struct {
	Fixtures  int `json:"fixtures"`
	Open      int `json:"open_markets"`
	Suspended int `json:"suspended_markets"`
	Settled   int `json:"settled_fixtures"`
	Gaps      int `json:"feed_gaps"`
}

// Totals sums the book.
func (b *Book) Totals() Totals {
	var t Totals
	for _, f := range b.All() {
		t.Fixtures++
		t.Open += f.OpenMarkets
		t.Suspended += f.SuspendedMarkets
		t.Gaps += f.Gaps
		if f.Settled {
			t.Settled++
		}
	}
	return t
}
