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
