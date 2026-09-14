#!/usr/bin/env bash
# Grant the migrator user the least-privilege ACLs one side of the migration
# needs. Runs inside the rpk helper of that cluster, which already carries the
# superuser credentials and the MIGRATOR_USER name:
#
#   docker compose exec -T rpk-source /scripts/migrator-acls.sh source
#   docker compose exec -T rpk-target /scripts/migrator-acls.sh target
#
# The operations follow the Redpanda Migrator documentation. READ on a topic
# grants DESCRIBE but not DESCRIBE_CONFIGS, and the migrator needs the latter
# to copy topic configuration, so it is granted explicitly. Running the script
# twice is harmless: creating an ACL that exists is a no-op.
set -euo pipefail

side=${1:-}
# rpk prints a table for every ACL it creates; keep the one list at the end.
acl() { rpk security acl create "$@" >/dev/null; }
principal="User:${MIGRATOR_USER:?MIGRATOR_USER is not set}"

case "$side" in
  # tag::source[]
  source)
    # Read every shop.* topic and its configuration.
    acl --allow-principal "$principal" \
      --operation read,describe_configs \
      --topic shop. --resource-pattern-type prefixed
    # Track its own progress in the redpanda-migrator group.
    acl --allow-principal "$principal" \
      --operation read --group redpanda-migrator
    # Read the committed offsets of the groups being migrated.
    acl --allow-principal "$principal" \
      --operation describe --group orders-service
    # List topics and consumer groups.
    acl --allow-principal "$principal" \
      --operation describe --cluster
    ;;
  # end::source[]
  # tag::target[]
  target)
    # Create shop.* topics, write records to them, add partitions, and read
    # their configuration. Nothing outside the shop. prefix.
    acl --allow-principal "$principal" \
      --operation create,write,alter,describe_configs \
      --topic shop. --resource-pattern-type prefixed
    # Commit translated offsets for the migrated group. OffsetCommit is
    # authorized against the group (READ) and against every topic it names
    # (READ), so the migrator needs READ on the migrated topics here too.
    acl --allow-principal "$principal" \
      --operation read --group orders-service
    acl --allow-principal "$principal" \
      --operation read --topic shop. --resource-pattern-type prefixed
    # List topics and groups on the target.
    acl --allow-principal "$principal" \
      --operation describe --cluster
    ;;
  # end::target[]
  *)
    echo "usage: migrator-acls.sh source|target" >&2
    exit 2
    ;;
esac

rpk security acl list --allow-principal "$principal"
