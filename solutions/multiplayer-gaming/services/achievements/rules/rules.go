// Package rules holds the achievement logic as pure functions over a
// per-player state, so it can be unit tested without Redpanda.
//
// The state is partition-local: every event of one player is on one
// partition of game.player-events (the record key is player_id), so the
// instance that owns the partition sees the complete, ordered history of the
// player and needs no shared store.
package rules

import (
	"time"

	"multiplayer-gaming/services/internal/gamepb"
)

// Unlock is one achievement earned by a player.
type Unlock struct {
	Achievement string
	Detail      string
}

// Rules are the thresholds. Defaults match the docs.
type Rules struct {
	HotStreakCount  int           // positive deltas in a row
	HotStreakWindow time.Duration // ... within this much event time
	VeteranMatches  int           // matches finished
}

// Default is the rule set the service runs with.
var Default = Rules{HotStreakCount: 3, HotStreakWindow: 30 * time.Second, VeteranMatches: 10}

// tag::state[]
// PlayerState is everything the rules need about one player: a small ring of
// recent positive score deltas, match counters, and the one-time unlocks.
type PlayerState struct {
	streak   []time.Time // times of consecutive positive deltas, newest last
	Wins     int
	Matches  int
	Unlocked map[string]bool
}

func NewPlayerState() *PlayerState {
	return &PlayerState{Unlocked: map[string]bool{}}
}

// end::state[]

// tag::apply[]
// Apply folds one event into the state and returns the achievements it
// unlocked. It never looks at the wall clock: hot streaks are judged on the
// events' own occurred_at, so a replayed topic produces the same unlocks.
func (r Rules) Apply(s *PlayerState, ev *gamepb.GameEvent) []Unlock {
	var out []Unlock
	switch e := ev.GetEvent().(type) {
	case *gamepb.GameEvent_ScoreChanged:
		if e.ScoreChanged.GetDelta() <= 0 {
			s.streak = s.streak[:0] // a penalty ends the streak
			return nil
		}
		t := ev.GetOccurredAt().AsTime()
		s.streak = append(s.streak, t)
		if len(s.streak) > r.HotStreakCount {
			s.streak = s.streak[len(s.streak)-r.HotStreakCount:]
		}
		if len(s.streak) == r.HotStreakCount && t.Sub(s.streak[0]) <= r.HotStreakWindow {
			out = append(out, Unlock{"hot_streak", "3 positive score changes within 30 seconds"})
			s.streak = s.streak[:0] // the next streak needs three more
		}
	case *gamepb.GameEvent_PlayerLeft:
		s.Matches++
		if e.PlayerLeft.GetWon() {
			s.Wins++
			if s.Wins == 1 && !s.Unlocked["first_win"] {
				s.Unlocked["first_win"] = true
				out = append(out, Unlock{"first_win", "won a match for the first time"})
			}
		}
		if s.Matches == r.VeteranMatches && !s.Unlocked["veteran"] {
			s.Unlocked["veteran"] = true
			out = append(out, Unlock{"veteran", "finished 10 matches"})
		}
	}
	return out
}

// end::apply[]
