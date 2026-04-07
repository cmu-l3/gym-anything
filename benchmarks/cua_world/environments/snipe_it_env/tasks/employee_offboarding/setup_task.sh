#!/bin/bash
echo "=== Setting up employee_offboarding task ==="
source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_time.txt

API_TOKEN=$(get_api_token)
if [ -z "$API_TOKEN" ]; then
    echo "CRITICAL: No API token found"
fi

get_id() {
    echo "$1" | jq -r '.payload.id // .id // empty' 2>/dev/null
}

# 1. Ensure basic statuses exist and get IDs
SL_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
SL_DEPLOYED_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Deployed' LIMIT 1" | tr -d '[:space:]')
SL_REPAIR_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Out for Repair' LIMIT 1" | tr -d '[:space:]')

if [ -z "$SL_REPAIR_ID" ]; then
    SL_REPAIR_ID=$(get_id "$(snipeit_api POST "statuslabels" '{"name":"Out for Repair","type":"undeployable","color":"#FF9800"}')")
fi

echo "$SL_READY_ID" > /tmp/sl_ready_id.txt
echo "$SL_REPAIR_ID" > /tmp/sl_repair_id.txt

# 2. Get models or create them if missing
MODEL_MBP_ID=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%MacBook Pro%' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MODEL_MBP_ID" ]; then
    MODEL_MBP_ID=$(get_id "$(snipeit_api POST "models" '{"name":"MacBook Pro 16","category_id":1,"manufacturer_id":1,"model_number":"MBP16"}')")
    if [ -z "$MODEL_MBP_ID" ]; then MODEL_MBP_ID=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]'); fi
fi

MODEL_MON_ID=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%U2723QE%' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MODEL_MON_ID" ]; then
    MODEL_MON_ID=$(get_id "$(snipeit_api POST "models" '{"name":"Dell U2723QE","category_id":1,"manufacturer_id":1,"model_number":"U2723QE"}')")
    if [ -z "$MODEL_MON_ID" ]; then MODEL_MON_ID=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]'); fi
fi

# 3. Create Sarah Chen user account
USER_RESP=$(snipeit_api POST "users" '{"first_name":"Sarah","last_name":"Chen","username":"schen","password":"Temp1234!","password_confirmation":"Temp1234!","email":"schen@company.com","activated":true}')
SARAH_ID=$(get_id "$USER_RESP")
if [ -z "$SARAH_ID" ]; then
    SARAH_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='schen' LIMIT 1" | tr -d '[:space:]')
fi

# Clean up assets if they somehow already exist
for tag in ASSET-SC01 ASSET-SC02 ASSET-SC03 ASSET-SC04; do
    snipeit_db_query "DELETE FROM assets WHERE asset_tag='$tag'"
done

# 4. Create the 4 assets
ASSET1_ID=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-SC01\",\"name\":\"Sarah MacBook Pro 16\",\"model_id\":${MODEL_MBP_ID:-1},\"status_id\":${SL_READY_ID},\"serial\":\"FVFZM3X8Q6LR\"}")")
ASSET2_ID=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-SC02\",\"name\":\"Sarah Dell Monitor\",\"model_id\":${MODEL_MON_ID:-1},\"status_id\":${SL_READY_ID},\"serial\":\"CN0KDMHP742\"}")")
ASSET3_ID=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-SC03\",\"name\":\"Sarah iPhone\",\"model_id\":${MODEL_MBP_ID:-1},\"status_id\":${SL_READY_ID},\"serial\":\"DNQXK0F2PH\"}")")
ASSET4_ID=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-SC04\",\"name\":\"Sarah Cisco Phone\",\"model_id\":${MODEL_MBP_ID:-1},\"status_id\":${SL_READY_ID},\"serial\":\"FCH2249A0PQ\"}")")

# 5. Check out the assets to Sarah
for ASSET_ID in $ASSET1_ID $ASSET2_ID $ASSET3_ID $ASSET4_ID; do
    if [ -n "$ASSET_ID" ]; then
        snipeit_api POST "hardware/${ASSET_ID}/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":${SARAH_ID},\"status_id\":${SL_DEPLOYED_ID},\"note\":\"Initial checkout\"}"
    fi
done

# 6. Record baseline state for collateral damage checking
echo "$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag NOT LIKE 'ASSET-SC0%' AND deleted_at IS NULL" | tr -d '[:space:]')" > /tmp/initial_other_asset_count.txt
echo "$(snipeit_db_query "SELECT COUNT(*) FROM users WHERE username != 'schen' AND deleted_at IS NULL" | tr -d '[:space:]')" > /tmp/initial_other_user_count.txt

# 7. Start Firefox and focus Snipe-IT
ensure_firefox_snipeit
navigate_firefox_to "http://localhost:8000"
sleep 2

take_screenshot /tmp/task_initial_state.png
echo "=== Setup complete ==="