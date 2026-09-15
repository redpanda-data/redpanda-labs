// Package sim generates a sports data feed that behaves like a provider's:
// bursty, ordered per fixture, and with occasional gaps and suspensions.
//
// It is seeded, so a reader who runs the walkthrough twice sees the same
// numbers, and so the expected output in the docs is not a lie. Nothing here
// talks to Redpanda.
package sim

import (
	"fmt"
	"math"
	"math/rand"
	"sort"

	"sports-data-fanout/services/internal/feed"
)

// Fixture is one match the feed reports on.
type Fixture struct {
	ID      string   `json:"id"`
	Home    string   `json:"home"`
	Away    string   `json:"away"`
	League  string   `json:"league"`
	Markets []string `json:"markets"`
}

// Config is the knobs docker-compose.yml exposes.
type Config struct {
	Seed         int64
	Fixtures     []Fixture
	Provider     string
	SuspendEvery int // every Nth market update suspends its market, 0 for never
	DropEvery    int // every Nth event is dropped before sending, to create a sequence gap

	// EventsPerFixture is how many events a match produces before it ends. A
	// real provider sends thousands over 90 minutes; the default here is the
	// smallest number that still gives the odds engine enough samples for a
	// 99th percentile to mean anything.
	EventsPerFixture int64
}

// Generator produces events one at a time, in provider order.
type Generator struct {
	cfg   Config
	rng   *rand.Rand
	state map[string]*fixtureState
	order []string
	next  int
	count int64
}

type fixtureState struct {
	fixture   Fixture
	seq       int64
	homeGoals int
	awayGoals int
	suspended map[string]bool
	prob      map[string]float64
	ended     bool
}

// New returns a generator. Fixtures are sorted by id so the sequence does not
// depend on the order the sample data happened to be written in.
func New(cfg Config) (*Generator, error) {
	if len(cfg.Fixtures) == 0 {
		return nil, fmt.Errorf("no fixtures")
	}
	if cfg.Provider == "" {
		cfg.Provider = "sportradar"
	}
	if cfg.EventsPerFixture <= 0 {
		cfg.EventsPerFixture = 250
	}
	fixtures := append([]Fixture(nil), cfg.Fixtures...)
	sort.Slice(fixtures, func(i, j int) bool { return fixtures[i].ID < fixtures[j].ID })
	cfg.Fixtures = fixtures

	g := &Generator{cfg: cfg, rng: rand.New(rand.NewSource(cfg.Seed)), state: map[string]*fixtureState{}}
	for _, f := range fixtures {
		markets := f.Markets
		if len(markets) == 0 {
			markets = []string{"match-odds"}
		}
		st := &fixtureState{fixture: f, suspended: map[string]bool{}, prob: map[string]float64{}}
		for _, m := range markets {
			// Start from a plausible book: the home side a little favoured.
			st.prob[m+"|home"] = 0.45
			st.prob[m+"|away"] = 0.30
			st.prob[m+"|draw"] = 0.25
		}
		g.state[f.ID] = st
		g.order = append(g.order, f.ID)
	}
	return g, nil
}

// tag::next[]
// Next returns the next event, and false once every fixture has ended.
//
// Events are produced fixture by fixture in a rotation rather than at random,
// which is what makes a per-fixture sequence number meaningful: consumers can
// detect a gap because the provider's order is the order events are sent.
func (g *Generator) Next(nowMillis int64) (feed.Event, bool) {
	for tries := 0; tries < len(g.order)*2; tries++ {
		id := g.order[g.next%len(g.order)]
		g.next++
		st := g.state[id]
		if st.ended {
			continue
		}
		g.count++
		ev := g.event(st, nowMillis)
		if g.cfg.DropEvery > 0 && g.count%int64(g.cfg.DropEvery) == 0 {
			// Dropped on the provider's side: the sequence number is consumed,
			// so the consumer sees a gap. This is the failure a feed has that a
			// queue does not, and the market-state service counts it.
			continue
		}
		return ev, true
	}
	return feed.Event{}, false
}

// end::next[]

func (g *Generator) event(st *fixtureState, nowMillis int64) feed.Event {
	st.seq++
	ev := feed.Event{
		FeedTS:    nowMillis,
		Seq:       st.seq,
		FixtureID: st.fixture.ID,
		Provider:  g.cfg.Provider,
		Extra: map[string]string{
			"league": st.fixture.League,
		},
	}

	markets := st.fixture.Markets
	if len(markets) == 0 {
		markets = []string{"match-odds"}
	}
	market := markets[g.rng.Intn(len(markets))]
	marketID := st.fixture.ID + ":" + market

	switch {
	case st.seq >= g.cfg.EventsPerFixture:
		st.ended = true
		ev.EventType = feed.TypeMatchEnd
		ev.Extra["score"] = fmt.Sprintf("%d-%d", st.homeGoals, st.awayGoals)
		return ev

	case st.seq%13 == 0:
		// A goal moves the book, which is why a score event is not just news.
		if g.rng.Intn(2) == 0 {
			st.homeGoals++
		} else {
			st.awayGoals++
		}
		g.shift(st, markets)
		ev.EventType = feed.TypeScore
		ev.Extra["score"] = fmt.Sprintf("%d-%d", st.homeGoals, st.awayGoals)
		return ev

	case st.seq%17 == 0:
		ev.EventType = feed.TypeInjury
		ev.MarketID = marketID
		ev.Extra["player"] = fmt.Sprintf("player-%d", g.rng.Intn(22)+1)
		return ev

	case g.cfg.SuspendEvery > 0 && st.seq%int64(g.cfg.SuspendEvery) == 0:
		if st.suspended[marketID] {
			st.suspended[marketID] = false
			ev.EventType = feed.TypeMarketResume
		} else {
			st.suspended[marketID] = true
			ev.EventType = feed.TypeMarketSuspend
		}
		ev.MarketID = marketID
		return ev

	default:
		selection := []string{"home", "away", "draw"}[g.rng.Intn(3)]
		ev.EventType = feed.TypeMarketUpdate
		ev.MarketID = marketID
		ev.Selection = selection
		ev.Probability = round4(st.prob[market+"|"+selection])
		return ev
	}
}

// shift nudges the book after a goal and renormalizes, so probabilities stay
// a distribution instead of drifting into nonsense over a long match.
//
// The clamp is applied BEFORE normalizing, and the bounds account for what
// normalizing then does: with the loser floored at 0.04 each, a home side
// clamped to 0.90 comes out at 0.90/0.98, about 0.918. Clamping to the
// priceable limit itself would not be enough, because dividing by a sum below
// 1 pushes the largest value back above it.
func (g *Generator) shift(st *fixtureState, markets []string) {
	for _, m := range markets {
		home := clamp(st.prob[m+"|home"] + 0.05)
		away := clamp(st.prob[m+"|away"] - 0.02)
		draw := clamp(st.prob[m+"|draw"] - 0.02)
		sum := home + away + draw
		st.prob[m+"|home"] = home / sum
		st.prob[m+"|away"] = away / sum
		st.prob[m+"|draw"] = draw / sum
	}
}

// The bounds are not arbitrary. With the book's overround, a probability above
// 1/(MinPrice*Overround), about 0.9337, implies a price under the 1.01 floor,
// and the odds engine rejects it as a provider error. A generator that emits
// unpriceable events would make every number in the walkthrough need an
// excuse, so the drift is bounded to stay inside what can be priced after
// normalization. TestEveryGeneratedProbabilityCanBePriced is the guard.
func clamp(p float64) float64 { return math.Max(0.04, math.Min(0.90, p)) }

func round4(f float64) float64 { return math.Round(f*10000) / 10000 }

// Suspended reports whether a market is currently suspended, for tests.
func (g *Generator) Suspended(fixtureID, marketID string) bool {
	return g.state[fixtureID].suspended[marketID]
}
