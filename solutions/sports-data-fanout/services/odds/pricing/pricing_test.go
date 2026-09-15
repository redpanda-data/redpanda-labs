package pricing

import (
	"errors"
	"math"
	"testing"

	"sports-data-fanout/services/internal/feed"
)

func update(prob float64) feed.Event {
	return feed.Event{EventType: feed.TypeMarketUpdate, Selection: "home", Probability: prob}
}

func TestPriceIncludesTheOverround(t *testing.T) {
	// A fair 0.50 shot is 2.00 before margin and 1.89 after it. If this number
	// moves, the book's margin moved, which is a decision, not a refactor.
	got, err := Price(update(0.50), false)
	if err != nil {
		t.Fatalf("Price: %v", err)
	}
	if math.Abs(got-1.89) > 0.005 {
		t.Fatalf("price = %v, want 1.89", got)
	}
}

func TestSuspendedMarketsPublishNoPrice(t *testing.T) {
	if _, err := Price(update(0.50), true); !errors.Is(err, ErrSuspended) {
		t.Fatalf("err = %v, want ErrSuspended", err)
	}
	// And the same event prices fine once the market resumes, so suspension is
	// the only reason it did not.
	if _, err := Price(update(0.50), false); err != nil {
		t.Fatalf("after resume: %v", err)
	}
}

func TestOnlyMarketUpdatesArePriceable(t *testing.T) {
	for _, typ := range []string{feed.TypeScore, feed.TypeInjury, feed.TypeMatchEnd, feed.TypeMarketSuspend} {
		ev := update(0.5)
		ev.EventType = typ
		if _, err := Price(ev, false); !errors.Is(err, ErrNotPriceable) {
			t.Fatalf("%s: err = %v, want ErrNotPriceable", typ, err)
		}
	}
	noSelection := update(0.5)
	noSelection.Selection = ""
	if _, err := Price(noSelection, false); !errors.Is(err, ErrNotPriceable) {
		t.Fatalf("no selection: err = %v, want ErrNotPriceable", err)
	}
}

func TestImpossibleProbabilitiesAreRejectedRatherThanPublished(t *testing.T) {
	for _, prob := range []float64{0, -0.1, 1, 1.5} {
		if _, err := Price(update(prob), false); !errors.Is(err, ErrOutOfRange) {
			t.Fatalf("probability %v: err = %v, want ErrOutOfRange", prob, err)
		}
	}
	// 0.00094 would price at over 1000, which is a provider error.
	if _, err := Price(update(0.0009), false); !errors.Is(err, ErrOutOfRange) {
		t.Fatalf("tiny probability: err = %v, want ErrOutOfRange", err)
	}
	// A near-certainty is rejected for the same reason, from the other end:
	// 0.94 with the overround implies 1.0036, under the 1.01 floor.
	if _, err := Price(update(0.94), false); !errors.Is(err, ErrOutOfRange) {
		t.Fatalf("0.94: err = %v, want ErrOutOfRange (it implies a price below MinPrice)", err)
	}
	// And the highest probability the feed can emit does price, so the floor
	// and the generator's clamp agree. If either moves, this fails.
	got, err := Price(update(0.93), false)
	if err != nil {
		t.Fatalf("0.93 must price, or the generator emits unpriceable events: %v", err)
	}
	if got < MinPrice {
		t.Fatalf("price %v is below MinPrice %v", got, MinPrice)
	}
}
