SET 'parallelism.default' = '3';

CREATE TABLE quota_demo_source (
  payload STRING
) WITH (
  'connector' = 'kafka',
  'topic' = 'quota-demo',
  'properties.bootstrap.servers' = 'redpanda-0:9092',
  'properties.group.id' = 'flink-quota-demo',
  'properties.client.id.prefix' = 'flink-quota-demo',
  'scan.startup.mode' = 'earliest-offset',
  'format' = 'raw'
);

CREATE TABLE sink (
  payload STRING
) WITH (
  'connector' = 'blackhole'
);

INSERT INTO sink SELECT * FROM quota_demo_source;
