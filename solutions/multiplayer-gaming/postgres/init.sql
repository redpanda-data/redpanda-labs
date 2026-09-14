-- Tables the Redpanda Connect pipeline (connect/match-history.yaml) writes.
-- Runs once, when the postgres volume is created.

-- tag::match_history[]
-- One row per finished match, from match_ended on game.match-events.
CREATE TABLE IF NOT EXISTS match_history (
  match_id         TEXT PRIMARY KEY,
  started_at       TIMESTAMPTZ,
  ended_at         TIMESTAMPTZ NOT NULL,
  duration_seconds INTEGER,
  winner_player_id TEXT,
  player_ids       JSONB NOT NULL,
  region           TEXT
);
-- end::match_history[]

-- tag::player_events[]
-- Every event on game.player-events, flattened. event_id is the primary key
-- and the pipeline inserts with ON CONFLICT DO NOTHING, so a redelivered
-- record (at-least-once) inserts nothing twice.
CREATE TABLE IF NOT EXISTS player_events (
  event_id    TEXT PRIMARY KEY,
  event_type  TEXT NOT NULL,
  player_id   TEXT NOT NULL,
  match_id    TEXT,
  occurred_at TIMESTAMPTZ NOT NULL,
  delta       BIGINT,
  new_score   BIGINT,
  item_id     TEXT,
  quantity    INTEGER,
  won         BOOLEAN,
  region      TEXT,
  payload     JSONB NOT NULL
);
CREATE INDEX IF NOT EXISTS player_events_player_idx ON player_events (player_id, occurred_at);
CREATE INDEX IF NOT EXISTS player_events_match_idx ON player_events (match_id);
-- end::player_events[]
