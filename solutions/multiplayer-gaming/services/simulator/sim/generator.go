// Package sim generates a deterministic stream of game events.
//
// Given the same seed and roster, two generators emit byte-for-byte identical
// sequences, including timestamps: the generator keeps its own simulated
// clock instead of reading the wall clock. That is what lets verify.sh
// assert exact counts and lets step 8 replay the topic into an identical
// leaderboard.
package sim

import (
	"fmt"
	"math/rand"
	"time"

	"google.golang.org/protobuf/types/known/timestamppb"

	"multiplayer-gaming/services/internal/gamepb"
)

// Player is one roster entry (sample-data/players.json).
type Player struct {
	ID          string `json:"id"`
	DisplayName string `json:"display_name"`
}

// Config controls the generator. Zero values take the defaults below.
type Config struct {
	Seed          int64
	Players       int           // roster size actually used
	Roster        []Player      // names; synthetic entries fill up to Players
	MatchSize     int           // players per match, default 4
	MatchDuration time.Duration // simulated match length, default 60s
	Tick          time.Duration // simulated time between events, default 200ms
	Region        string
	Start         time.Time // simulated clock start, fixed by default
}

// Topics the generator writes to.
const (
	TopicPlayerEvents = "game.player-events"
	TopicMatchEvents  = "game.match-events"
	TopicAchievements = "game.achievements"
)

type match struct {
	id        string
	mode      string
	players   []string
	scores    map[string]int64
	startedAt time.Time
}

// Generator is not safe for concurrent use.
type Generator struct {
	cfg     Config
	rng     *rand.Rand
	now     time.Time
	seq     int64
	matches int
	running []*match
	idle    []string
	names   map[string]string
	pending []*gamepb.GameEvent
	counts  map[string]int64
}

// New builds a generator. Same Config, same events.
func New(cfg Config) *Generator {
	if cfg.MatchSize <= 0 {
		cfg.MatchSize = 4
	}
	if cfg.MatchDuration <= 0 {
		cfg.MatchDuration = 60 * time.Second
	}
	if cfg.Tick <= 0 {
		cfg.Tick = 200 * time.Millisecond
	}
	if cfg.Players <= 0 {
		cfg.Players = 24
	}
	if cfg.Start.IsZero() {
		cfg.Start = time.Date(2026, 9, 1, 12, 0, 0, 0, time.UTC)
	}
	g := &Generator{
		cfg:    cfg,
		rng:    rand.New(rand.NewSource(cfg.Seed)),
		now:    cfg.Start,
		names:  map[string]string{},
		counts: map[string]int64{},
	}
	for i := 0; i < cfg.Players; i++ {
		var p Player
		if i < len(cfg.Roster) {
			p = cfg.Roster[i]
		} else {
			p = Player{ID: fmt.Sprintf("p%03d", i+1), DisplayName: fmt.Sprintf("Player %d", i+1)}
		}
		g.idle = append(g.idle, p.ID)
		g.names[p.ID] = p.DisplayName
	}
	return g
}

// Counts returns how many events of each type have been returned by Next.
func (g *Generator) Counts() map[string]int64 {
	out := make(map[string]int64, len(g.counts))
	for k, v := range g.counts {
		out[k] = v
	}
	return out
}

// Now is the simulated clock.
func (g *Generator) Now() time.Time { return g.now }

// tag::next[]
// Next returns exactly one event. Multi-event moments (a match starting or
// ending) are queued and drained one per call, so a caller that stops after
// N calls has produced exactly N records and never half a match ending.
func (g *Generator) Next() *gamepb.GameEvent {
	for len(g.pending) == 0 {
		g.now = g.now.Add(g.cfg.Tick)
		g.step()
	}
	ev := g.pending[0]
	g.pending = g.pending[1:]
	g.counts[EventType(ev)]++
	return ev
}

// end::next[]

// tag::step[]
// step advances the simulated clock by one tick: fill the lobby, end a match
// that has run its length, or let one player in a running match score or pick
// up an item.
func (g *Generator) step() {
	// Fill the lobby: every group of MatchSize idle players starts a match.
	if len(g.idle) >= g.cfg.MatchSize {
		g.startMatch()
		return
	}
	if len(g.running) == 0 {
		return
	}
	m := g.running[g.rng.Intn(len(g.running))]
	if g.now.Sub(m.startedAt) >= g.cfg.MatchDuration {
		g.endMatch(m)
		return
	}
	pid := m.players[g.rng.Intn(len(m.players))]
	if g.rng.Intn(100) < 70 {
		delta := g.delta()
		m.scores[pid] += delta
		g.emit(pid, m.id, &gamepb.GameEvent_ScoreChanged{ScoreChanged: &gamepb.ScoreChanged{
			Delta: delta, NewScore: m.scores[pid], Reason: reasonFor(delta),
		}})
		return
	}
	g.emit(pid, m.id, &gamepb.GameEvent_ItemAcquired{ItemAcquired: &gamepb.ItemAcquired{
		ItemId: items[g.rng.Intn(len(items))], Quantity: int32(1 + g.rng.Intn(3)),
	}})
}

// end::step[]

// delta is mostly positive so leaderboards climb; the negatives are what
// break hot streaks.
func (g *Generator) delta() int64 {
	r := g.rng.Intn(100)
	switch {
	case r < 30:
		return 5
	case r < 60:
		return 10
	case r < 75:
		return 15
	case r < 85:
		return 25
	case r < 95:
		return -5
	default:
		return -10
	}
}

func reasonFor(delta int64) string {
	switch {
	case delta >= 25:
		return "objective"
	case delta > 0:
		return "elimination"
	default:
		return "penalty"
	}
}

var items = []string{"shield", "medkit", "boost", "scope", "grenade", "key"}
var modes = []string{"capture", "deathmatch", "survival"}

func (g *Generator) startMatch() {
	g.matches++
	m := &match{
		id:        fmt.Sprintf("m-%05d", g.matches),
		mode:      modes[g.rng.Intn(len(modes))],
		scores:    map[string]int64{},
		startedAt: g.now,
	}
	for i := 0; i < g.cfg.MatchSize; i++ {
		k := g.rng.Intn(len(g.idle))
		pid := g.idle[k]
		g.idle = append(g.idle[:k], g.idle[k+1:]...)
		m.players = append(m.players, pid)
		m.scores[pid] = 0
	}
	g.running = append(g.running, m)
	g.emit("", m.id, &gamepb.GameEvent_MatchStarted{MatchStarted: &gamepb.MatchStarted{
		PlayerIds: append([]string(nil), m.players...), Mode: m.mode,
	}})
	for _, pid := range m.players {
		g.emit(pid, m.id, &gamepb.GameEvent_PlayerJoined{PlayerJoined: &gamepb.PlayerJoined{DisplayName: g.names[pid]}})
	}
}

func (g *Generator) endMatch(m *match) {
	winner := m.players[0]
	for _, pid := range m.players[1:] {
		if m.scores[pid] > m.scores[winner] {
			winner = pid
		}
	}
	// One PlayerLeft per participant, keyed by player, so a consumer that owns
	// a player's partition learns that player's result without reading
	// game.match-events.
	for _, pid := range m.players {
		g.emit(pid, m.id, &gamepb.GameEvent_PlayerLeft{PlayerLeft: &gamepb.PlayerLeft{
			Won: pid == winner, FinalScore: m.scores[pid],
		}})
	}
	g.emit("", m.id, &gamepb.GameEvent_MatchEnded{MatchEnded: &gamepb.MatchEnded{
		PlayerIds:       append([]string(nil), m.players...),
		WinnerPlayerId:  winner,
		DurationSeconds: int64(g.now.Sub(m.startedAt) / time.Second),
		StartedAt:       timestamppb.New(m.startedAt),
	}})
	for i, r := range g.running {
		if r == m {
			g.running = append(g.running[:i], g.running[i+1:]...)
			break
		}
	}
	g.idle = append(g.idle, m.players...)
}

func (g *Generator) emit(playerID, matchID string, payload any) {
	g.seq++
	ev := &gamepb.GameEvent{
		EventId:    fmt.Sprintf("evt-%08d", g.seq),
		PlayerId:   playerID,
		MatchId:    matchID,
		OccurredAt: timestamppb.New(g.now),
	}
	if g.cfg.Region != "" {
		ev.Region = &g.cfg.Region
	}
	switch p := payload.(type) {
	case *gamepb.GameEvent_ScoreChanged:
		ev.Event = p
	case *gamepb.GameEvent_ItemAcquired:
		ev.Event = p
	case *gamepb.GameEvent_MatchStarted:
		ev.Event = p
	case *gamepb.GameEvent_MatchEnded:
		ev.Event = p
	case *gamepb.GameEvent_PlayerJoined:
		ev.Event = p
	case *gamepb.GameEvent_PlayerLeft:
		ev.Event = p
	}
	g.pending = append(g.pending, ev)
}

// tag::routing[]
// EventType names the oneof case; it is also the value of the event_type
// record header.
func EventType(ev *gamepb.GameEvent) string {
	switch ev.GetEvent().(type) {
	case *gamepb.GameEvent_PlayerJoined:
		return "player_joined"
	case *gamepb.GameEvent_PlayerLeft:
		return "player_left"
	case *gamepb.GameEvent_MatchStarted:
		return "match_started"
	case *gamepb.GameEvent_MatchEnded:
		return "match_ended"
	case *gamepb.GameEvent_ScoreChanged:
		return "score_changed"
	case *gamepb.GameEvent_ItemAcquired:
		return "item_acquired"
	case *gamepb.GameEvent_AchievementUnlocked:
		return "achievement_unlocked"
	}
	return "unknown"
}

// Topic and Key route an event: match lifecycle on game.match-events keyed by
// match_id, everything about a player on game.player-events keyed by
// player_id. Same key, same partition, so one player's events stay in order.
func Topic(ev *gamepb.GameEvent) string {
	switch ev.GetEvent().(type) {
	case *gamepb.GameEvent_MatchStarted, *gamepb.GameEvent_MatchEnded:
		return TopicMatchEvents
	case *gamepb.GameEvent_AchievementUnlocked:
		return TopicAchievements
	}
	return TopicPlayerEvents
}

func Key(ev *gamepb.GameEvent) string {
	if Topic(ev) == TopicMatchEvents {
		return ev.GetMatchId()
	}
	return ev.GetPlayerId()
}

// end::routing[]
