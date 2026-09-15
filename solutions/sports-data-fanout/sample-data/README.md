# Sample data

`fixtures.json` is the list of matches the feed service reports on: four
fixtures across four leagues, with two or three markets each. The names are
invented.

It is deliberately small. The feed's volume comes from the event rate
(`FEED_RATE`) and the length of a match, not from the number of fixtures, and
four fixtures across six partitions is enough to show that one fixture's
events stay in order on one partition while the others are processed in
parallel.

Add a fixture and the feed picks it up on the next `make seed`: nothing else
needs changing. Remove one and the topic still holds its events, which is the
point of a log.

`fixtures-late.json` is the two matches that kick off later in the day. The
schema evolution step (`make evolve`) restarts the feed against this file, so
the events it writes under the new schema version are events the topic has
never seen: a provider's own `(fixture, seq)` pair is the identity of an
event, and re-sending the same four matches would be a redelivery rather than
new data.
