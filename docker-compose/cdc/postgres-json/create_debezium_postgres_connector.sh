#! /bin/bash

docker compose exec debezium `curl -H 'Content-Type: application/json' debezium:8083/connectors --data '
{
  "name": "postgres-connector",  
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector", 
    "plugin.name": "pgoutput",
    "database.hostname": "postgres", 
    "database.port": "5432", 
    "database.user": "postgresuser", 
    "database.password": "postgrespw", 
    "database.dbname" : "pandashop", 
    "database.server.name": "postgres", 
    "table.include.list": "public.orders",
    "topic.prefix" : "dbz"
  }
}'