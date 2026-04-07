#!/bin/bash
echo "=== Setting up asset_model_normalization task ==="
source /workspace/scripts/task_utils.sh

# 1. Retrieve necessary foreign keys for Snipe-IT relations
MFG_LENOVO=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name LIKE '%Lenovo%' LIMIT 1" | tr -d '[:space:]')
MFG_DELL=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name LIKE '%Dell%' LIMIT 1" | tr -d '[:space:]')
CAT_LAPTOPS=$(snipeit_db_query "SELECT id FROM categories WHERE name LIKE '%Laptops%' LIMIT 1" | tr -d '[:space:]')
CAT_MONITORS=$(snipeit_db_query "SELECT id FROM categories WHERE name LIKE '%Monitors%' LIMIT 1" | tr -d '[:space:]')
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# Helper to extract ID from API responses
get_id() { echo "$1" | jq -r '.payload.id // .id // empty' 2>/dev/null; }

# 2. Inject duplicate and canonical models via Snipe-IT API
echo "Creating canonical and duplicate models..."
CANONICAL_LAPTOP=$(get_id "$(snipeit_api POST "models" "{\"name\":\"ThinkPad T14 Gen 2\", \"category_id\":$CAT_LAPTOPS, \"manufacturer_id\":$MFG_LENOVO}")")
DUP_LAPTOP_1=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Lenovo T14\", \"category_id\":$CAT_LAPTOPS, \"manufacturer_id\":$MFG_LENOVO}")")
DUP_LAPTOP_2=$(get_id "$(snipeit_api POST "models" "{\"name\":\"ThinkPad T-14G2\", \"category_id\":$CAT_LAPTOPS, \"manufacturer_id\":$MFG_LENOVO}")")

CANONICAL_MONITOR=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Dell UltraSharp U2720Q\", \"category_id\":$CAT_MONITORS, \"manufacturer_id\":$MFG_DELL}")")
DUP_MONITOR_1=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Dell U2720Q\", \"category_id\":$CAT_MONITORS, \"manufacturer_id\":$MFG_DELL}")")
DUP_MONITOR_2=$(get_id "$(snipeit_api POST "models" "{\"name\":\"27-inch Dell Monitor\", \"category_id\":$CAT_MONITORS, \"manufacturer_id\":$MFG_DELL}")")

# Save IDs for export script
echo "$CANONICAL_LAPTOP" > /tmp/canonical_laptop_id.txt
echo "$CANONICAL_MONITOR" > /tmp/canonical_monitor_id.txt
echo "$DUP_LAPTOP_1,$DUP_LAPTOP_2" > /tmp/dup_laptop_ids.txt
echo "$DUP_MONITOR_1,$DUP_MONITOR_2" > /tmp/dup_monitor_ids.txt

# 3. Inject assets attached ONLY to the duplicate models
echo "Creating 9 assets attached to dirty models..."
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-NORM-01\",\"status_id\":$SL_READY,\"model_id\":$DUP_LAPTOP_1,\"name\":\"Marketing Laptop A\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-NORM-02\",\"status_id\":$SL_READY,\"model_id\":$DUP_LAPTOP_1,\"name\":\"Marketing Laptop B\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-NORM-03\",\"status_id\":$SL_READY,\"model_id\":$DUP_LAPTOP_1,\"name\":\"Sales Laptop A\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-NORM-04\",\"status_id\":$SL_READY,\"model_id\":$DUP_LAPTOP_2,\"name\":\"Sales Laptop B\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-NORM-05\",\"status_id\":$SL_READY,\"model_id\":$DUP_LAPTOP_2,\"name\":\"HR Laptop A\"}"

snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-NORM-06\",\"status_id\":$SL_READY,\"model_id\":$DUP_MONITOR_1,\"name\":\"Desk 21 Monitor\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-NORM-07\",\"status_id\":$SL_READY,\"model_id\":$DUP_MONITOR_1,\"name\":\"Desk 22 Monitor\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-NORM-08\",\"status_id\":$SL_READY,\"model_id\":$DUP_MONITOR_2,\"name\":\"Conf Room Screen 1\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-NORM-09\",\"status_id\":$SL_READY,\"model_id\":$DUP_MONITOR_2,\"name\":\"Conf Room Screen 2\"}"

sleep 2

# 4. Record baseline state for verification to detect collateral damage
echo "Recording baseline state..."
TOTAL_MODELS_BEFORE=$(snipeit_db_query "SELECT COUNT(*) FROM models WHERE deleted_at IS NULL" | tr -d '[:space:]')
TOTAL_ASSETS_BEFORE=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE deleted_at IS NULL" | tr -d '[:space:]')
echo "$TOTAL_MODELS_BEFORE" > /tmp/total_models_before.txt
echo "$TOTAL_ASSETS_BEFORE" > /tmp/total_assets_before.txt
date +%s > /tmp/task_start_time.txt

# 5. UI startup
ensure_firefox_snipeit
navigate_firefox_to "http://localhost:8000/models"
sleep 2
take_screenshot /tmp/asset_model_normalization_initial.png

echo "=== setup complete ==="