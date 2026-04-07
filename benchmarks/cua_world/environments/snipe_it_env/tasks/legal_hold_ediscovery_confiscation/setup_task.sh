#!/bin/bash
echo "=== Setting up legal_hold_ediscovery_confiscation task ==="

source /workspace/scripts/task_utils.sh

# Ensure Snipe-IT is open
ensure_firefox_snipeit
sleep 2

# Retrieve random Model ID and 'Ready to Deploy' Status ID via DB
MDL_ID=$(snipeit_db_query "SELECT id FROM models WHERE deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
STAT_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

echo "Using Model ID: $MDL_ID, Status ID: $STAT_ID"

# Inject User function
inject_user() {
    local fname=$1
    local lname=$2
    local uname=$3
    local resp=$(snipeit_api POST "users" "{\"first_name\":\"$fname\",\"last_name\":\"$lname\",\"username\":\"$uname\",\"password\":\"password123\",\"password_confirmation\":\"password123\"}")
    echo "$resp" | jq -r '.payload.id // .id // empty' 2>/dev/null
}

echo "Injecting target and distractor users..."
U1_ID=$(inject_user "Marcus" "Vance" "mvance")
U2_ID=$(inject_user "Elena" "Rostova" "erostova")
U3_ID=$(inject_user "David" "Chen" "dchen")
U4_ID=$(inject_user "Sarah" "Smith" "ssmith")

echo "Users created: $U1_ID, $U2_ID, $U3_ID, $U4_ID"

# Inject Asset and Checkout function
inject_asset_and_checkout() {
    local tag=$1
    local name=$2
    local uid=$3
    local aid_resp=$(snipeit_api POST "hardware" "{\"asset_tag\":\"$tag\",\"name\":\"$name\",\"model_id\":$MDL_ID,\"status_id\":$STAT_ID}")
    local aid=$(echo "$aid_resp" | jq -r '.payload.id // .id // empty' 2>/dev/null)
    if [ -n "$aid" ] && [ -n "$uid" ]; then
        snipeit_api POST "hardware/$aid/checkout" "{\"assigned_user\":$uid,\"checkout_to_type\":\"user\",\"note\":\"Initial allocation\"}" > /dev/null
    fi
}

echo "Injecting assets for targets..."
inject_asset_and_checkout "ASSET-LH01" "Marcus Primary Laptop" "$U1_ID"
inject_asset_and_checkout "ASSET-LH02" "Marcus Mobile Device" "$U1_ID"
inject_asset_and_checkout "ASSET-LH03" "Elena Dev Workstation" "$U2_ID"
inject_asset_and_checkout "ASSET-LH04" "Elena Tablet" "$U2_ID"
inject_asset_and_checkout "ASSET-LH05" "David Presentation Laptop" "$U3_ID"
inject_asset_and_checkout "ASSET-LH06" "David Phone" "$U3_ID"

echo "Injecting assets for distractors..."
inject_asset_and_checkout "ASSET-DS01" "Sarah Primary Laptop" "$U4_ID"
inject_asset_and_checkout "ASSET-DS02" "Sarah Mobile" "$U4_ID"

sleep 3

# Record baseline for distractors to verify they remain untouched
snipeit_db_query "SELECT asset_tag, assigned_to, status_id, rtd_location_id, notes FROM assets WHERE asset_tag IN ('ASSET-DS01', 'ASSET-DS02') AND deleted_at IS NULL" > /tmp/distractor_baseline.txt

# Timestamp task initialization for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Return to Snipe-IT Dashboard
navigate_firefox_to "http://localhost:8000/hardware"
sleep 2

# Initial evidence collection
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="