package rules

import (
	"testing"
	"time"

	"google.golang.org/protobuf/types/known/timestamppb"

	"multiplayer-gaming/services/internal/gamepb"
)

var t0 = time.Date(2026, 9, 1, 12, 0, 0, 0, time.UTC)

func score(at time.Duration, delta int64) *gamepb.GameEvent {
	return &gamepb.GameEvent{PlayerId: "p1", OccurredAt: timestamppb.New(t0.Add(at)),
		Event: &gamepb.GameEvent_ScoreChanged{ScoreChanged: &gamepb.ScoreChanged{Delta: delta}}}
}

func left(won bool) *gamepb.GameEvent {
	return &gamepb.GameEvent{PlayerId: "p1", OccurredAt: timestamppb.New(t0),
		Event: &gamepb.GameEvent_PlayerLeft{PlayerLeft: &gamepb.PlayerLeft{Won: won}}}
}

func names(us []Unlock) []string {
	var out []string
	for _, u := range us {
		out = append(out, u.Achievement)
	}
	return out
}

func TestHotStreakThreePositivesWithinWindow(t *testing.T) {
	s := NewPlayerState()
	if u := Default.Apply(s, score(0, 5)); len(u) != 0 {
		t.Fatalf("unexpected %v", names(u))
	}
	if u := Default.Apply(s, score(10*time.Second, 10)); len(u) != 0 {
		t.Fatalf("unexpected %v", names(u))
	}
	u := Default.Apply(s, score(29*time.Second, 15))
	if len(u) != 1 || u[0].Achievement != "hot_streak" {
		t.Fatalf("want hot_streak, got %v", names(u))
	}
}

func TestHotStreakTooSlowDoesNotFire(t *testing.T) {
	s := NewPlayerState()
	Default.Apply(s, score(0, 5))
	Default.Apply(s, score(20*time.Second, 5))
	if u := Default.Apply(s, score(31*time.Second, 5)); len(u) != 0 {
		t.Fatalf("streak spanning 31s must not fire, got %v", names(u))
	}
	// The window slides: the last three (20s, 31s, 40s) are within 30s.
	if u := Default.Apply(s, score(40*time.Second, 5)); len(u) != 1 {
		t.Fatalf("sliding window should fire, got %v", names(u))
	}
}

func TestNegativeDeltaResetsStreak(t *testing.T) {
	s := NewPlayerState()
	Default.Apply(s, score(0, 5))
	Default.Apply(s, score(time.Second, 5))
	Default.Apply(s, score(2*time.Second, -5))
	if u := Default.Apply(s, score(3*time.Second, 5)); len(u) != 0 {
		t.Fatalf("streak must restart after a penalty, got %v", names(u))
	}
	Default.Apply(s, score(4*time.Second, 5))
	if u := Default.Apply(s, score(5*time.Second, 5)); len(u) != 1 {
		t.Fatalf("three positives after the reset should fire, got %v", names(u))
	}
}

func TestHotStreakFiresOncePerStreak(t *testing.T) {
	s := NewPlayerState()
	fired := 0
	for i := 0; i < 6; i++ {
		fired += len(Default.Apply(s, score(time.Duration(i)*time.Second, 5)))
	}
	if fired != 2 {
		t.Fatalf("six positives are two streaks, got %d unlocks", fired)
	}
}

func TestFirstWinOnlyOnce(t *testing.T) {
	s := NewPlayerState()
	if u := Default.Apply(s, left(false)); len(u) != 0 {
		t.Fatalf("a loss unlocks nothing, got %v", names(u))
	}
	if u := Default.Apply(s, left(true)); len(u) != 1 || u[0].Achievement != "first_win" {
		t.Fatalf("want first_win, got %v", names(u))
	}
	if u := Default.Apply(s, left(true)); len(u) != 0 {
		t.Fatalf("second win unlocks nothing, got %v", names(u))
	}
}

func TestVeteranAfterTenMatches(t *testing.T) {
	s := NewPlayerState()
	for i := 1; i <= 9; i++ {
		if u := Default.Apply(s, left(false)); len(u) != 0 {
			t.Fatalf("match %d unlocked %v", i, names(u))
		}
	}
	u := Default.Apply(s, left(false))
	if len(u) != 1 || u[0].Achievement != "veteran" {
		t.Fatalf("want veteran on match 10, got %v", names(u))
	}
	if u := Default.Apply(s, left(false)); len(u) != 0 {
		t.Fatalf("match 11 unlocked %v", names(u))
	}
}

func TestTenthMatchWinUnlocksBoth(t *testing.T) {
	s := NewPlayerState()
	for i := 0; i < 9; i++ {
		Default.Apply(s, left(false))
	}
	u := names(Default.Apply(s, left(true)))
	if len(u) != 2 || u[0] != "first_win" || u[1] != "veteran" {
		t.Fatalf("want [first_win veteran], got %v", u)
	}
}

// A produce that fails after Apply has already advanced the state loses the
// unlock: on replay the streak is spent and nothing is re-emitted. The service
// snapshots with Clone and restores on failure, so these two tests pin the
// behaviour that makes the rollback work.
func TestCloneIsADeepCopy(t *testing.T) {
	s := NewPlayerState()
	Default.Apply(s, score(0, 5))
	Default.Apply(s, score(time.Second, 5))
	s.Wins, s.Matches = 3, 7

	c := s.Clone()

	// Advancing the original must not touch the clone.
	Default.Apply(s, score(2*time.Second, 5))
	s.Wins, s.Matches = 99, 99
	s.Unlocked["first_win"] = true

	if len(c.streak) != 2 {
		t.Fatalf("clone streak moved with the original: got %d, want 2", len(c.streak))
	}
	if c.Wins != 3 || c.Matches != 7 {
		t.Fatalf("clone counters moved with the original: got wins=%d matches=%d, want 3 and 7", c.Wins, c.Matches)
	}
	if c.Unlocked["first_win"] {
		t.Fatal("clone Unlocked map is shared with the original, so it is not a deep copy")
	}
}

func TestRestoringACloneLetsTheUnlockFireAgain(t *testing.T) {
	s := NewPlayerState()
	Default.Apply(s, score(0, 5))
	Default.Apply(s, score(time.Second, 5))

	// The event that unlocks hot_streak. Snapshot first, as the service does.
	before := s.Clone()
	third := score(2*time.Second, 5)
	if got := names(Default.Apply(s, third)); len(got) != 1 || got[0] != "hot_streak" {
		t.Fatalf("setup: third positive delta should unlock hot_streak, got %v", got)
	}

	// Negative control: without a rollback, replaying loses the unlock. This is
	// the bug, asserted so a future change cannot quietly reintroduce it.
	if got := names(Default.Apply(s, third)); len(got) != 0 {
		t.Fatalf("replay without rollback should emit nothing, got %v", got)
	}

	// With the rollback, the replay re-derives it.
	*s = *before
	if got := names(Default.Apply(s, third)); len(got) != 1 || got[0] != "hot_streak" {
		t.Fatalf("replay after restoring the snapshot should unlock hot_streak again, got %v", got)
	}
}
