#!/bin/bash
# Compare subjects and versions between the source Confluent Schema Registry
# and the destination Schema Registry on the Redpanda shadow cluster.
set -e

SOURCE_SR="${SOURCE_SR:-http://localhost:8081}"
DEST_SR="${DEST_SR:-http://localhost:28081}"

# Print a subject's compatibility setting, or note that it inherits the global
# one. A subject with no subject-level override returns HTTP 404 with error
# code 40408, which is expected and not a replication failure.
compatibility() {
  local base="$1" subject="$2" body
  body=$(curl -s "${base}/config/${subject}")
  if echo "${body}" | grep -q '"error_code":40408'; then
    echo "(none set; inherits the global default)"
  else
    echo "${body}"
  fi
}

report() {
  local label="$1" base="$2" subject
  echo "=== ${label} ==="
  echo "Subjects:"
  curl -s "${base}/subjects"
  echo
  for subject in orders-value customers-value; do
    echo "${label} versions for ${subject}:"
    curl -s "${base}/subjects/${subject}/versions"
    echo
    echo "${label} compatibility for ${subject}: $(compatibility "${base}" "${subject}")"
  done
  echo
}

report "SOURCE" "${SOURCE_SR}"
report "DESTINATION" "${DEST_SR}"

echo "If replication has caught up, both sides list the same subjects,"
echo "the same version numbers, and the same compatibility setting."
