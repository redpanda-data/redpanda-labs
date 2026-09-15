// Package pricing turns a provider probability into the price a book shows.
//
// The arithmetic is deliberately simple: this solution is about moving prices
// to every consumer that needs them, not about being a trading desk. What
// matters is that the rules are explicit and testable, because "why did this
// selection publish no price" is the first question anyone asks of a feed.
package pricing

import (
	"errors"
	"math"

	"sports-data-fanout/services/internal/feed"
)

// Overround is the book's margin over the provider's implied probability.
// 1.06 means the book prices a fair 2.00 shot at about 1.89.
const Overround = 1.06

// Limits on what is publishable. A price outside them is a data error, not a
// long shot: publishing it would put a wrong number on every screen.
const (
	MinPrice = 1.01
	MaxPrice = 1000.0
)

var (
	// ErrNotPriceable is not a failure: the event was never about a price.
	ErrNotPriceable = errors.New("event does not carry a priceable selection")
	// ErrSuspended means the market is closed, so the last price stands.
	ErrSuspended = errors.New("market is suspended")
	// ErrOutOfRange means the provider sent a probability that cannot be a price.
	ErrOutOfRange = errors.New("probability is out of range")
)

// tag::price[]
// Price returns decimal odds for one market update.
//
// suspended is the caller's view of the market, because suspension arrives as
// its own event type and the price of a suspended market must not move.
func Price(ev feed.Event, suspended bool) (float64, error) {
	if ev.EventType != feed.TypeMarketUpdate || ev.Selection == "" {
		return 0, ErrNotPriceable
	}
	if suspended {
		return 0, ErrSuspended
	}
	if ev.Probability <= 0 || ev.Probability >= 1 {
		return 0, ErrOutOfRange
	}
	price := 1 / (ev.Probability * Overround)
	if price < MinPrice || price > MaxPrice {
		return 0, ErrOutOfRange
	}
	return math.Round(price*100) / 100, nil
}

// end::price[]
