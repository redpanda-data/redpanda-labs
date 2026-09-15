-- The settlement and audit store. Every event the feed published lands here
-- exactly as it arrived, because a sportsbook has to be able to answer "what
-- did the provider tell us, and when" months later, for a regulator or a
-- customer dispute.
--
-- Redpanda Connect writes this table (see connect/feed-archive.yaml). Nothing
-- reads it in the walkthrough except the reader.

CREATE TABLE IF NOT EXISTS feed_archive (
  -- The provider's own identity for the event. A feed that redelivers must not
  -- create a second row, so the primary key is the provider's, not ours.
  fixture_id  TEXT        NOT NULL,
  seq         BIGINT      NOT NULL,
  event_type  TEXT        NOT NULL,
  market_id   TEXT        NOT NULL DEFAULT '',
  selection   TEXT        NOT NULL DEFAULT '',
  probability DOUBLE PRECISION,
  feed_ts     BIGINT      NOT NULL,
  provider    TEXT        NOT NULL DEFAULT '',
  archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (fixture_id, seq)
);

-- "Show me everything for this match in provider order" is the query the
-- settlement team runs, so it gets the index.
CREATE INDEX IF NOT EXISTS feed_archive_fixture_seq ON feed_archive (fixture_id, seq);

-- And the audit question: what arrived in this window, across all fixtures.
CREATE INDEX IF NOT EXISTS feed_archive_feed_ts ON feed_archive (feed_ts);
