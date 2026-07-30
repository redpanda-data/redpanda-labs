#!/bin/bash
# Compare subjects and versions between the source Confluent Schema Registry
# and the destination Schema Registry on the Redpanda shadow cluster.
set -e

SOURCE_SR="${SOURCE_SR:-http://localhost:8081}"
DEST_SR="${DEST_SR:-http://localhost:28081}"

echo "=== Source (Confluent Schema Registry) ==="
echo "Subjects:"
curl -s "${SOURCE_SR}/subjects"
echo
for subject in orders-value customers-value; do
  echo "Versions for ${subject}:"
  curl -s "${SOURCE_SR}/subjects/${subject}/versions"
  echo
  echo "Compatibility for ${subject}:"
  curl -s "${SOURCE_SR}/config/${subject}"
  echo
done

echo
echo "=== Destination (Redpanda shadow cluster Schema Registry) ==="
echo "Subjects:"
curl -s "${DEST_SR}/subjects"
echo
for subject in orders-value customers-value; do
  echo "Versions for ${subject}:"
  curl -s "${DEST_SR}/subjects/${subject}/versions"
  echo
  echo "Compatibility for ${subject}:"
  curl -s "${DEST_SR}/config/${subject}"
  echo
done

echo
echo "If replication has caught up, both sides should list the same subjects,"
echo "the same version numbers, and the same compatibility setting."
