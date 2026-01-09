#!/bin/bash

echo "Setting up topics on both clusters..."

# Create topic on primary cluster
echo "Creating topic on primary cluster..."
docker exec primary-broker-0 rpk topic create failover-demo-topic \
    --partitions 3 \
    --replicas 3 \
    --brokers primary-broker-0:9092,primary-broker-1:9092,primary-broker-2:9092

# Create topic on secondary cluster
echo "Creating topic on secondary cluster..."
docker exec secondary-broker-0 rpk topic create failover-demo-topic \
    --partitions 3 \
    --replicas 3 \
    --brokers secondary-broker-0:9092,secondary-broker-1:9092,secondary-broker-2:9092

# Verify topics
echo "Verifying topics..."
echo "Primary cluster topics:"
docker exec primary-broker-0 rpk topic list --brokers primary-broker-0:9092,primary-broker-1:9092,primary-broker-2:9092

echo "Secondary cluster topics:"
docker exec secondary-broker-0 rpk topic list --brokers secondary-broker-0:9092,secondary-broker-1:9092,secondary-broker-2:9092

echo "Topics created on both clusters"
echo "Note: Each cluster has independent data - no replication configured"
echo "Setup complete!"
