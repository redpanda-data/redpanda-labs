# MySQL CDC with Debezium and Redpanda

![Architecture](./images/architecture.png)

## Overview
This sample demonstrates using Debezium to capture the changes made to MySQL in real time and stream them to Redpanda.

This read-to-run `docker-compose` setup contains the following containers:
- `mysql` container with the `pandashop` database, containing a single table, `orders`
- `debezium` container captuing changes made to the `orders` table in real time. 
- `redpanda` container to ingest change data streams produced by `debezium`

For more information about `pandashop` schema, refer to the `/data/mysql_bootstrap.sql` file.

## Set up guide

### Start the containers
Start the set up by running:

```
docker compose up -d
```

Wait until you get the status of all containers as `running` or `running (healthy)` after executing `docker compose ps`.

### Verify the database
Upon `mysql` container startup, the `/data/mysql_bootstrap.sql` file creates the `pandashop` database and the `orders` table, followed by seeding the ` orders` table with a few records.

To verify that, log into MySQL by running:

```sql
docker compose exec mysql mysql -u mysqluser -p
```

Provide `mysqlpw` as the password when prompted.

Then check the content inside the `orders` table as:

```sql
use pandashop;
show tables;
select * from orders;
```

This is going to be our source table.

### Create a MySQL source connector configuration for Debezium
While Debezium is up and running, let's create a source connector configuration to extract change data feeds from MySQL.

```
docker compose exec debezium curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" localhost:8083/connectors/ -d '
 {
  "name": "mysql-connector",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "tasks.max": "1",
    "database.hostname": "mysql",
    "database.port": "3306",
    "database.user": "debezium",
    "database.password": "dbz",
    "database.server.id": "184054",
    "topic.prefix": "dbz",
    "database.include.list": "pandashop",
    "schema.history.internal.kafka.bootstrap.servers": "redpanda:9092",
    "schema.history.internal.kafka.topic": "schemahistory.pandashop"
  }
}'
```

Notice the `database.*` configurations specifying the connectivity details to `mysql` container. The parameter, `schema.history.internal.kafka.bootstrap.servers` points to the `redpanda` broker the connector uses to write and recover DDL statements to the database schema history topic.

Wait a minute or two until the connector gets deployed inside Debezium and creates the initial snapshot of change log topics in Redpanda. 

### Verify change log topics in Redpanda
Next, check the list of change log topics in `redpanda` by running:

```
docker-compose exec redpanda rpk topic list
```

You will see two topics with the prefix `dbz.*` specified in the connector configuration. The topic `dbz.pandashop.orders` holds the initial snapshot of change log events streamed from `orders` table.

```
NAME                     PARTITIONS  REPLICAS
connect-status           5           1
connect_configs          1           1
connect_offsets          25          1
dbz                      1           1
dbz.pandashop.orders     1           1
schemahistory.pandashop  1           1
```

Finally, you can see the shape of change events by consuming the `dbz.pandashop.orders` topic.

```
docker-compose exec redpanda rpk topic consume dbz.pandashop.orders 
```

You should see JSON formatted change events.

While the consumer is running, let's open another terminal to insert a record to the `orders` table.

```
docker-compose exec mysql mysql -u mysqluser -p
```

Provide `mysqlpw` as the password when prompted.

Then insert the following record:

```sql
use pandashop;
INSERT INTO orders (customer_id, total) values (5, 500);
```

This will trigger a change event in Debezium, immediately publishing it to `dbz.pandashop.orders` Redpanda topic, causing the consumer to display a new event in the console. That proves the end to end functionality of our CDC pipeline.

## What's next?
Now that you have change log events ingested into Redpanda. You process change log events to enable use cases such as:
- Database replication
- Stream processing applications
- Streaming ETL pipelines
- Update caches
- Event-driven Microservices

etc.