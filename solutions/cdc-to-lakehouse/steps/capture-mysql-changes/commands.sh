#!/usr/bin/env bash
# Commands the 'capture-mysql-changes' page shows, one tagged region per command block.
# The page includes each region; the generated Doc Detective spec runs the
# same region; tools/capture-expected.sh writes its stdout to expected/<tag>.txt.

# tag::start[]
make cdc-mysql
# end::start[]

# tag::binlog[]
docker compose exec -T mysql mysql -N -s -u root -ppandashop-root \
  -e "SHOW VARIABLES LIKE 'binlog_format'; SHOW VARIABLES LIKE 'binlog_row_image';"
# end::binlog[]

# tag::wait[]
make wait-lakehouse ROWS=10
# end::wait[]

# tag::verify[]
make query-freshness
# end::verify[]
