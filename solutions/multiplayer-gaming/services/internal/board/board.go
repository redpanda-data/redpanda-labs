// Package board reads the compacted topic game.leaderboard.
//
// The topic is the leaderboard: one LeaderboardEntry per player, the latest
// one wins. Both readers of it live here. The dashboard streams it from the
// start and keeps a map; the leaderboard service takes a snapshot of it when
// it is handed a game.player-events partition, to learn where its players'
// totals stop. Neither reader joins a consumer group: a materialized view is
// read from the beginning, and every reader needs all of it.
package board

import (
	"context"
	"errors"
	"fmt"
	"log"
	"sort"
	"time"

	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"
	"github.com/twmb/franz-go/pkg/sr"

	"multiplayer-gaming/services/internal/gamepb"
	"multiplayer-gaming/services/internal/schema"
	"multiplayer-gaming/services/internal/topics"
)

// Topic is the compacted leaderboard topic.
const Topic = "game.leaderboard"

// tag::reader[]
// Reader consumes the leaderboard topic from the first record with no
// consumer group and no commits. It decodes each record through Schema
// Registry and tracks how far it has read in every partition.
type Reader struct {
	cl       *kgo.Client
	adm      *kadm.Client
	dec      *schema.Decoder
	topic    string
	position map[int32]int64 // next offset to read, per partition
	records  int64
}

// Open waits for Schema Registry, the topic's subject, and the topic itself,
// then returns a Reader positioned at the start of every partition.
func Open(ctx context.Context, brokers []string, srURL, topic, clientID string) (*Reader, error) {
	srClient, err := sr.NewClient(sr.URLs(srURL))
	if err != nil {
		return nil, fmt.Errorf("schema registry client: %w", err)
	}
	if err := schema.WaitForRegistry(ctx, srClient); err != nil {
		return nil, err
	}
	var dec *schema.Decoder
	for {
		dec, err = schema.NewMessageDecoder(ctx, srClient, schema.Subject(topic), &gamepb.LeaderboardEntry{})
		if err == nil {
			break
		}
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		log.Printf("waiting for subject %s: %v", schema.Subject(topic), err)
		time.Sleep(2 * time.Second)
	}
	cl, err := kgo.NewClient(
		kgo.SeedBrokers(brokers...),
		kgo.ClientID(clientID),
		kgo.ConsumeTopics(topic),
		kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()),
	)
	if err != nil {
		return nil, fmt.Errorf("kafka client: %w", err)
	}
	topics.Wait(ctx, cl, topic)
	if ctx.Err() != nil {
		cl.Close()
		return nil, ctx.Err()
	}
	return &Reader{cl: cl, adm: kadm.NewClient(cl), dec: dec, topic: topic, position: map[int32]int64{}}, nil
}

// Close releases the client.
func (r *Reader) Close() { r.cl.Close() }

// Poll fetches the next records and calls fn for each. A record with an empty
// value is a tombstone: fn receives a nil entry and should forget the key.
// Records whose schema ID is not registered under the subject are logged and
// skipped. Poll returns after one fetch; call it in a loop.
func (r *Reader) Poll(ctx context.Context, fn func(key string, e *gamepb.LeaderboardEntry, rec *kgo.Record)) error {
	fetches := r.cl.PollRecords(ctx, 1000)
	if fetches.IsClientClosed() {
		return errors.New("client closed")
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	fetches.EachError(func(t string, p int32, err error) { log.Printf("fetch %s/%d: %v", t, p, err) })
	fetches.EachRecord(func(rec *kgo.Record) {
		r.position[rec.Partition] = rec.Offset + 1
		r.records++
		if len(rec.Value) == 0 {
			fn(string(rec.Key), nil, rec)
			return
		}
		var e gamepb.LeaderboardEntry
		if err := r.dec.DecodeInto(ctx, rec.Value, &e); err != nil {
			log.Printf("skipping %s/%d@%d: %v", rec.Topic, rec.Partition, rec.Offset, err)
			return
		}
		fn(string(rec.Key), &e, rec)
	})
	return nil
}

// Records is how many records Poll has delivered so far.
func (r *Reader) Records() int64 { return r.records }

// EndOffsets returns the current high watermark of every partition.
func (r *Reader) EndOffsets(ctx context.Context) (map[int32]int64, error) {
	ends, err := r.adm.ListEndOffsets(ctx, r.topic)
	if err != nil {
		return nil, err
	}
	out := map[int32]int64{}
	ends.Each(func(o kadm.ListedOffset) { out[o.Partition] = o.Offset })
	return out, nil
}

// CaughtUp reports whether the reader has consumed every partition up to the
// given end offsets.
func (r *Reader) CaughtUp(ends map[int32]int64) bool {
	for p, end := range ends {
		if r.position[p] < end {
			return false
		}
	}
	return len(ends) > 0
}

// end::reader[]

// tag::snapshot[]
// Snapshot reads the topic from the start to the end offsets observed when it
// is called and returns the last entry per key. On a compacted topic that is
// the whole board: one entry per player.
func Snapshot(ctx context.Context, brokers []string, srURL, topic, clientID string) (map[string]*gamepb.LeaderboardEntry, error) {
	r, err := Open(ctx, brokers, srURL, topic, clientID)
	if err != nil {
		return nil, err
	}
	defer r.Close()
	ends, err := r.EndOffsets(ctx)
	if err != nil {
		return nil, fmt.Errorf("end offsets of %s: %w", topic, err)
	}
	entries := map[string]*gamepb.LeaderboardEntry{}
	for !r.CaughtUp(ends) {
		pollCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		err := r.Poll(pollCtx, func(key string, e *gamepb.LeaderboardEntry, _ *kgo.Record) {
			if e == nil {
				delete(entries, key)
				return
			}
			entries[key] = e
		})
		cancel()
		if err != nil && ctx.Err() != nil {
			return nil, ctx.Err()
		}
	}
	return entries, nil
}

// end::snapshot[]

// Ranked is one row of the board as the dashboard serves it.
type Ranked struct {
	Rank        int    `json:"rank"`
	PlayerID    string `json:"player_id"`
	DisplayName string `json:"display_name"`
	Score       int64  `json:"score"`
}

// Top ranks the entries by score, highest first, ties broken by player_id so
// two readers of the same topic always agree on the order, and returns the
// first n.
func Top(entries map[string]*gamepb.LeaderboardEntry, n int) []Ranked {
	all := make([]*gamepb.LeaderboardEntry, 0, len(entries))
	for _, e := range entries {
		all = append(all, e)
	}
	sort.Slice(all, func(i, j int) bool {
		if all[i].GetScore() != all[j].GetScore() {
			return all[i].GetScore() > all[j].GetScore()
		}
		return all[i].GetPlayerId() < all[j].GetPlayerId()
	})
	if n > len(all) {
		n = len(all)
	}
	out := make([]Ranked, 0, n)
	for i, e := range all[:n] {
		out = append(out, Ranked{Rank: i + 1, PlayerID: e.GetPlayerId(), DisplayName: e.GetDisplayName(), Score: e.GetScore()})
	}
	return out
}
