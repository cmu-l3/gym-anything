#!/bin/bash
echo "=== Setting up telecom_sim_card_provisioning task ==="

source /workspace/scripts/task_utils.sh

# 1. Create target assets: MOB-001, MOB-002, MOB-003
echo "Checking dependencies for Mobile assets..."
SL_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
MDL_IPHONE=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%iPhone%' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MDL_IPHONE" ] || [ "$MDL_IPHONE" = "NULL" ]; then
    echo "iPhone model not found, falling back to any available model"
    MDL_IPHONE=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]')
fi

# Ensure previous MOB tags don't exist
for tag in "MOB-001" "MOB-002" "MOB-003" "SIM-001" "SIM-002" "SIM-003"; do
    if asset_exists_by_tag "$tag"; then
        snipeit_db_query "DELETE FROM assets WHERE asset_tag='$tag'"
    fi
done

echo "Creating Mobile assets..."
snipeit_api POST "hardware" "{\"asset_tag\":\"MOB-001\",\"name\":\"Delivery iPhone - Unit A\",\"model_id\":$MDL_IPHONE,\"status_id\":$SL_READY_ID,\"serial\":\"IPHONE-A\"}" > /dev/null
snipeit_api POST "hardware" "{\"asset_tag\":\"MOB-002\",\"name\":\"Delivery iPhone - Unit B\",\"model_id\":$MDL_IPHONE,\"status_id\":$SL_READY_ID,\"serial\":\"IPHONE-B\"}" > /dev/null
snipeit_api POST "hardware" "{\"asset_tag\":\"MOB-003\",\"name\":\"Delivery iPhone - Unit C\",\"model_id\":$MDL_IPHONE,\"status_id\":$SL_READY_ID,\"serial\":\"IPHONE-C\"}" > /dev/null

# Verify MOBs were created
MOB1_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='MOB-001' AND deleted_at IS NULL" | tr -d '[:space:]')
MOB2_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='MOB-002' AND deleted_at IS NULL" | tr -d '[:space:]')
MOB3_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='MOB-003' AND deleted_at IS NULL" | tr -d '[:space:]')
echo "MOB IDs: $MOB1_ID, $MOB2_ID, $MOB3_ID"

# 2. Record initial counts to detect DO-NOTHING gaming
INITIAL_ASSET_COUNT=$(get_asset_count)
echo "$INITIAL_ASSET_COUNT" > /tmp/initial_asset_count.txt

INITIAL_CUSTOM_FIELDS=$(snipeit_db_query "SELECT COUNT(*) FROM custom_fields" | tr -d '[:space:]')
echo "$INITIAL_CUSTOM_FIELDS" > /tmp/initial_custom_fields.txt

# Timestamp
date +%s > /tmp/task_start_time.txt

# 3. Open Firefox to start the task
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/telecom_initial.png

echo "=== setup complete ==="