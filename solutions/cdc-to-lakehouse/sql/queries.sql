-- Queries the query-with-spark step runs, one per tagged region. Each is run
-- with `docker compose exec -T spark spark-sql -f /sql/queries.sql`, or by
-- name through the Makefile (`make query-changes`, `make query-current`).

-- tag::tables[]
SHOW TABLES IN lakehouse.redpanda;
-- end::tables[]

-- tag::columns[]
DESCRIBE TABLE lakehouse.redpanda.cdc_orders;
-- end::columns[]

-- tag::changes[]
SELECT op, source, order_id, customer_id, total, status
FROM lakehouse.redpanda.cdc_orders
ORDER BY source, order_id, captured_at;
-- end::changes[]

-- tag::current[]
-- The table is an append-only log of row changes, which is what a lakehouse
-- wants: you reconstruct the current state with a window function over the
-- change log and drop the rows whose last change was a delete.
WITH latest AS (
  SELECT *, ROW_NUMBER() OVER (
           PARTITION BY source, order_id ORDER BY captured_at DESC, position DESC
         ) AS recency
  FROM lakehouse.redpanda.cdc_orders
)
SELECT source, order_id, customer_id, total, status, op AS last_change
FROM latest
WHERE recency = 1 AND op <> 'delete'
ORDER BY source, order_id;
-- end::current[]

-- tag::freshness[]
-- How far behind the database the lakehouse is, per source.
SELECT source,
       COUNT(*) AS changes,
       MAX(captured_at) AS newest_change
FROM lakehouse.redpanda.cdc_orders
GROUP BY source
ORDER BY source;
-- end::freshness[]

-- tag::count[]
SELECT COUNT(*) FROM lakehouse.redpanda.cdc_orders;
-- end::count[]

-- tag::summary[]
-- One line with every count scripts/verify.sh checks, so the whole
-- verification needs one Spark driver instead of six.
SELECT concat_ws(' ',
         concat('total=',    count(*)),
         concat('postgres=', sum(CASE WHEN source = 'postgres' THEN 1 ELSE 0 END)),
         concat('mysql=',    sum(CASE WHEN source = 'mysql'    THEN 1 ELSE 0 END)),
         concat('snapshot=', sum(CASE WHEN op = 'snapshot' THEN 1 ELSE 0 END)),
         concat('insert=',   sum(CASE WHEN op = 'insert'   THEN 1 ELSE 0 END)),
         concat('update=',   sum(CASE WHEN op = 'update'   THEN 1 ELSE 0 END)),
         concat('delete=',   sum(CASE WHEN op = 'delete'   THEN 1 ELSE 0 END)))
FROM lakehouse.redpanda.cdc_orders;
-- end::summary[]

-- tag::current_count[]
WITH latest AS (
  SELECT *, ROW_NUMBER() OVER (
           PARTITION BY source, order_id ORDER BY captured_at DESC, position DESC
         ) AS recency
  FROM lakehouse.redpanda.cdc_orders
)
SELECT count(*) FROM latest
WHERE recency = 1 AND op <> 'delete' AND source = 'postgres';
-- end::current_count[]
