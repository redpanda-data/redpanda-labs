#!/usr/bin/env bash
# Print what the manifests in kubernetes/ would deploy, and check that they
# still agree with the shadow link the compose stack creates.
#
#   ./scripts/check-kubernetes.sh
#
# Run it before `kubectl apply`, and after editing a manifest. It needs no
# cluster and no kubectl: it reads the files. It fails when a manifest is
# missing a field the walkthrough relies on, or when the Kubernetes link and
# config/shadow-link.yaml stopped matching, which is the way these two copies
# of the same link drift apart.
set -uo pipefail
cd "$(dirname "$0")/.."

errors=0
fail() { errors=$((errors + 1)); printf 'check-kubernetes: %s\n' "$1" >&2; }

# value <file> <key>: the value of the first `key: value` line, unquoted.
value() { sed -nE "s/^[[:space:]]*$2:[[:space:]]*[\"']?([^\"'#]+[^\"' #])[\"']?[[:space:]]*$/\1/p" "$1" | head -1; }

cluster() {
  local file=$1 want_ns=$2 want_id=$3 want_port=$4
  [ -f "$file" ] || { fail "$file is missing"; return; }
  local ns image id linking port
  ns=$(value "$file" namespace)
  image=$(value "$file" tag)
  id=$(value "$file" cluster_id)
  linking=$(value "$file" enable_shadow_linking)
  port=$(sed -nE 's/^[[:space:]]*-[[:space:]]*([0-9]{4,5})[[:space:]]*$/\1/p' "$file" | head -1)
  printf '%s: namespace %s, Redpanda %s, cluster_id %s, shadow linking %s, external Kafka port %s\n' \
    "$file" "$ns" "$image" "$id" "$linking" "$port"
  [ "$ns" = "$want_ns" ] || fail "$file: namespace is '$ns', expected '$want_ns'"
  [ "$id" = "$want_id" ] || fail "$file: cluster_id is '$id', expected '$want_id'"
  [ "$linking" = "true" ] || fail "$file: enable_shadow_linking is '$linking', expected 'true'"
  [ "$port" = "$want_port" ] || fail "$file: advertised external Kafka port is '$port', expected '$want_port'"
}

cluster kubernetes/source-cluster.yaml source dr-source 19094
cluster kubernetes/shadow-cluster.yaml shadow dr-shadow 29094

link=kubernetes/shadow-link.yaml
if [ ! -f "$link" ]; then
  fail "$link is missing"
else
  name=$(value "$link" name)
  mode=$(value "$link" schema_registry_shadowing_mode)
  topic_prefix=$(awk '/topicMetadataSyncOptions/,/consumerOffsetSyncOptions/' "$link" | sed -nE 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.+)$/\1/p' | head -1)
  group_prefix=$(awk '/consumerOffsetSyncOptions/,/schemaRegistrySyncOptions/' "$link" | sed -nE 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.+)$/\1/p' | head -1)
  printf '%s: ShadowLink %s reads redpanda.source.svc.cluster.local and writes redpanda.shadow.svc.cluster.local\n' "$link" "$name"
  printf '%s: topics with prefix %s, consumer groups with prefix %s, Schema Registry mode %s\n' \
    "$link" "$topic_prefix" "$group_prefix" "$mode"
  # The operator's NameFilter accepts only `literal` or `prefixed`, and
  # rejects the `prefix` that reads more naturally, so check it here rather
  # than finding out from a rejected resource.
  bad=$(grep -c 'patternType:[[:space:]]*prefix[[:space:]]*$' "$link")
  [ "$bad" -eq 0 ] || fail "$link: patternType must be 'prefixed', not 'prefix' ($bad occurrence(s))"
  [ "$(grep -c 'patternType:[[:space:]]*prefixed' "$link")" -eq 2 ] || fail "$link: both filters must use patternType: prefixed"
  grep -q 'startOffset:[[:space:]]*earliest' "$link" || fail "$link: startOffset must be earliest, to match start_at_earliest in config/shadow-link.yaml"
  grep -q 'redpanda.source.svc.cluster.local:9093' "$link" || fail "$link: the source cluster brokers are not redpanda.source.svc.cluster.local:9093"
  grep -q 'redpanda.shadow.svc.cluster.local:9093' "$link" || fail "$link: the shadow cluster brokers are not redpanda.shadow.svc.cluster.local:9093"

  # The compose stack and Kubernetes describe the same link twice. Keep the
  # filters identical, or a reader who follows both gets two different links.
  compose=config/shadow-link.yaml
  compose_topic=$(awk '/topic_metadata_sync_options/,/consumer_offset_sync_options/' "$compose" | sed -nE 's/^[[:space:]]*name:[[:space:]]*(.+)$/\1/p' | head -1)
  compose_group=$(awk '/consumer_offset_sync_options/,/schema_registry_sync_options/' "$compose" | sed -nE 's/^[[:space:]]*name:[[:space:]]*(.+)$/\1/p' | head -1)
  [ "$topic_prefix" = "$compose_topic" ] || fail "topic filter is '$topic_prefix' here and '$compose_topic' in $compose"
  [ "$group_prefix" = "$compose_group" ] || fail "group filter is '$group_prefix' here and '$compose_group' in $compose"
  grep -q 'shadow_schema_registry_topic' "$compose" && [ "$mode" = "topic" ] \
    || fail "Schema Registry replication mode is '$mode' here and something else in $compose"
  printf 'the filters match %s, so both paths create the same link\n' "$compose"
fi

if [ $errors -eq 0 ]; then
  printf '3 manifest(s) ready to apply\n'
  exit 0
fi
printf '%d problem(s) found\n' "$errors" >&2
exit 1
