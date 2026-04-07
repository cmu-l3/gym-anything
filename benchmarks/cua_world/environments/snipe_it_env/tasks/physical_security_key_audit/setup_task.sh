#!/bin/bash
echo "=== Setting up physical_security_key_audit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up potential previous state to ensure idempotency
echo "Cleaning up any previous task artifacts..."
snipeit_db_query "DELETE FROM assets WHERE asset_tag IN ('ASSET-KEY-004', 'ASSET-KEY-009', 'ASSET-KEY-015')"
snipeit_db_query "DELETE FROM users WHERE username IN ('sharding', 'dnedry')"
snipeit_db_query "DELETE FROM models WHERE name IN ('Standard Physical Key', 'RFID Access Badge')"
snipeit_db_query "DELETE FROM categories WHERE name='Building Keys'"
snipeit_db_query "DELETE FROM custom_fields WHERE name IN ('Key Cut Code', 'Access Zone')"
snipeit_db_query "DELETE FROM custom_fieldsets WHERE name='Physical Security Keys'"
sleep 1

# 2. Inject realistic task data via API and DB queries
echo "Injecting task data..."

# Users
snipeit_api POST "users" '{"first_name":"Sarah","last_name":"Harding","username":"sharding","password":"password123","password_confirmation":"password123","email":"sharding@example.com"}' > /dev/null
snipeit_api POST "users" '{"first_name":"Dennis","last_name":"Nedry","username":"dnedry","password":"password123","password_confirmation":"password123","email":"dnedry@example.com"}' > /dev/null

USER_SHARDING_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='sharding' LIMIT 1" | tr -d '[:space:]')
USER_DNEDRY_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='dnedry' LIMIT 1" | tr -d '[:space:]')

# Categories & Manufacturers
snipeit_api POST "categories" '{"name":"Building Keys","category_type":"asset"}' > /dev/null
CAT_KEYS_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Building Keys' LIMIT 1" | tr -d '[:space:]')

MANUFACTURER_ID=$(snipeit_db_query "SELECT id FROM manufacturers LIMIT 1" | tr -d '[:space:]')
if [ -z "$MANUFACTURER_ID" ]; then
    snipeit_api POST "manufacturers" '{"name":"Generic Security"}' > /dev/null
    MANUFACTURER_ID=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Generic Security' LIMIT 1" | tr -d '[:space:]')
fi

# Models
snipeit_api POST "models" "{\"name\":\"Standard Physical Key\",\"category_id\":$CAT_KEYS_ID,\"manufacturer_id\":$MANUFACTURER_ID}" > /dev/null
snipeit_api POST "models" "{\"name\":\"RFID Access Badge\",\"category_id\":$CAT_KEYS_ID,\"manufacturer_id\":$MANUFACTURER_ID}" > /dev/null

MODEL_KEY_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='Standard Physical Key' LIMIT 1" | tr -d '[:space:]')
MODEL_BADGE_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='RFID Access Badge' LIMIT 1" | tr -d '[:space:]')

# Status Label
STATUS_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# Assets
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-KEY-004\",\"name\":\"Zone B Master Key\",\"model_id\":$MODEL_KEY_ID,\"status_id\":$STATUS_READY_ID}" > /dev/null
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-KEY-009\",\"name\":\"Spare Zone B Master Key\",\"model_id\":$MODEL_KEY_ID,\"status_id\":$STATUS_READY_ID}" > /dev/null
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-KEY-015\",\"name\":\"Visitor Badge 15\",\"model_id\":$MODEL_BADGE_ID,\"status_id\":$STATUS_READY_ID}" > /dev/null

ASSET_004_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='ASSET-KEY-004' LIMIT 1" | tr -d '[:space:]')
ASSET_009_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='ASSET-KEY-009' LIMIT 1" | tr -d '[:space:]')
ASSET_015_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='ASSET-KEY-015' LIMIT 1" | tr -d '[:space:]')

# Checkout target assets to target users to set initial state
snipeit_api POST "hardware/${ASSET_004_ID}/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$USER_SHARDING_ID}" > /dev/null
snipeit_api POST "hardware/${ASSET_015_ID}/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$USER_DNEDRY_ID}" > /dev/null

# 3. Save IDs for verification later
date +%s > /tmp/task_start_time.txt
echo "$ASSET_004_ID" > /tmp/asset_004_id.txt
echo "$ASSET_009_ID" > /tmp/asset_009_id.txt
echo "$ASSET_015_ID" > /tmp/asset_015_id.txt
echo "$CAT_KEYS_ID" > /tmp/cat_keys_id.txt
echo "$USER_SHARDING_ID" > /tmp/user_sharding_id.txt

# 4. Environment readiness
ensure_firefox_snipeit
navigate_firefox_to "http://localhost:8000"
sleep 2

# Take initial screenshot showing clean dashboard
take_screenshot /tmp/task_initial.png

echo "=== physical_security_key_audit setup complete ==="