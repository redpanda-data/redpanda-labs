#!/bin/bash
# Setup script for Redpanda Migrator Demo with Security
# Creates users, ACLs, topics, and schemas for secure migration

set -e

SOURCE_BROKERS="redpanda-source:9092"
TARGET_BROKERS="redpanda-target:9092"
TARGET_SCHEMA_REGISTRY="http://redpanda-target:8081"

# Admin credentials (bootstrapped)
ADMIN_USER="admin-user"
ADMIN_PASS="admin-secret-password"

# Migrator credentials
MIGRATOR_USER="migrator-user"
MIGRATOR_PASS="migrator-secret-password"

echo "========================================="
echo "Redpanda Migrator Demo - Secure Setup"
echo "========================================="
echo ""

# ====================
# STEP 1: Create Users
# ====================
echo "1. Creating users..."
echo ""

# Create migrator-user on source
echo "  Creating migrator-user on source cluster..."
rpk security user create "$MIGRATOR_USER" \
  --password "$MIGRATOR_PASS" \
  --api-urls "redpanda-source:9644" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS"

# Create migrator-user on target
echo "  Creating migrator-user on target cluster..."
rpk security user create "$MIGRATOR_USER" \
  --password "$MIGRATOR_PASS" \
  --api-urls "redpanda-target:9644" \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS"

echo "  ✅ Users created!"
echo ""

# ===================================
# STEP 2: Configure Superusers & Enable Authorization
# ===================================
echo "2. Configuring superusers and enabling authorization..."
echo ""

echo "  Setting admin-user as superuser on source cluster..."
rpk cluster config set superusers '["admin-user"]' \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X admin.hosts=redpanda-source:9644

echo "  Setting admin-user as superuser on target cluster..."
rpk cluster config set superusers '["admin-user"]' \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X admin.hosts=redpanda-target:9644

echo "  Enabling authorization on source cluster..."
rpk cluster config set kafka_enable_authorization true \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X admin.hosts=redpanda-source:9644

echo "  Enabling authorization on target cluster..."
rpk cluster config set kafka_enable_authorization true \
  -X user="$ADMIN_USER" \
  -X pass="$ADMIN_PASS" \
  -X admin.hosts=redpanda-target:9644

echo "  ✅ Superusers configured and authorization enabled!"
echo ""

echo "========================================="
echo "✅ Pre-Restart Setup Complete!"
echo "=========================================" 
echo ""
echo "⚠️  Clusters will now be restarted to apply authorization changes."
