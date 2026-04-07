#!/bin/bash
set -e
echo "=== Setting up oem_license_hardware_assignment task ==="
source /workspace/scripts/task_utils.sh

get_id() {
    echo "$1" | jq -r '.payload.id // .id // empty' 2>/dev/null
}

SL_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
SL_RETIRED_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Retired' LIMIT 1" | tr -d '[:space:]')

# Create Manufacturers
BMD_ID=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"Blackmagic Design"}')")
if [ -z "$BMD_ID" ]; then BMD_ID=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Blackmagic Design' LIMIT 1" | tr -d '[:space:]'); fi

MAXON_ID=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"Maxon"}')")
if [ -z "$MAXON_ID" ]; then MAXON_ID=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Maxon' LIMIT 1" | tr -d '[:space:]'); fi

# Create Categories
CAT_ASSET_ID=$(get_id "$(snipeit_api POST "categories" '{"name":"Render Nodes","category_type":"asset"}')")
if [ -z "$CAT_ASSET_ID" ]; then CAT_ASSET_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Render Nodes' LIMIT 1" | tr -d '[:space:]'); fi

CAT_LIC_ID=$(get_id "$(snipeit_api POST "categories" '{"name":"Software","category_type":"license"}')")
if [ -z "$CAT_LIC_ID" ]; then CAT_LIC_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Software' LIMIT 1" | tr -d '[:space:]'); fi

# Create Model
MODEL_ID=$(get_id "$(snipeit_api POST "models" '{"name":"Custom Render Node G1","category_id":'$CAT_ASSET_ID',"manufacturer_id":'$BMD_ID'}')")
if [ -z "$MODEL_ID" ]; then MODEL_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='Custom Render Node G1' LIMIT 1" | tr -d '[:space:]'); fi

# Create Physical Assets
for i in {1..4}; do
    snipeit_api POST "hardware" "{\"asset_tag\":\"RENDER-NODE-0$i\",\"name\":\"Render Node 0$i\",\"model_id\":$MODEL_ID,\"status_id\":$SL_READY_ID}"
done

ASSET1_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RENDER-NODE-01' LIMIT 1" | tr -d '[:space:]')
ASSET2_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RENDER-NODE-02' LIMIT 1" | tr -d '[:space:]')
ASSET3_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RENDER-NODE-03' LIMIT 1" | tr -d '[:space:]')
ASSET4_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RENDER-NODE-04' LIMIT 1" | tr -d '[:space:]')

# Create License "Maxon Redshift"
REDSHIFT_ID=$(get_id "$(snipeit_api POST "licenses" '{"name":"Maxon Redshift","seats":5,"manufacturer_id":'$MAXON_ID',"category_id":'$CAT_LIC_ID'}')")
if [ -z "$REDSHIFT_ID" ]; then REDSHIFT_ID=$(snipeit_db_query "SELECT id FROM licenses WHERE name='Maxon Redshift' LIMIT 1" | tr -d '[:space:]'); fi

# Checkout one seat of Redshift to RENDER-NODE-04 via DB directly
SEAT_ID=$(snipeit_db_query "SELECT id FROM license_seats WHERE license_id=$REDSHIFT_ID AND assigned_to IS NULL AND asset_id IS NULL LIMIT 1" | tr -d '[:space:]')
if [ -n "$SEAT_ID" ]; then
    snipeit_db_query "UPDATE license_seats SET asset_id=$ASSET4_ID, updated_at=NOW() WHERE id=$SEAT_ID"
fi

echo "$REDSHIFT_ID" > /tmp/redshift_id.txt
echo "$BMD_ID" > /tmp/bmd_id.txt
echo "$ASSET1_ID" > /tmp/asset1_id.txt
echo "$ASSET2_ID" > /tmp/asset2_id.txt
echo "$ASSET3_ID" > /tmp/asset3_id.txt
echo "$ASSET4_ID" > /tmp/asset4_id.txt
echo "$SL_RETIRED_ID" > /tmp/sl_retired_id.txt

# Initial states and timestamp
date +%s > /tmp/task_start_time.txt
USER_SEATS_BASELINE=$(snipeit_db_query "SELECT COUNT(*) FROM license_seats WHERE assigned_to IS NOT NULL AND assigned_to > 0" | tr -d '[:space:]')
echo "${USER_SEATS_BASELINE:-0}" > /tmp/user_seats_baseline.txt

# Start agent GUI sequence
ensure_firefox_snipeit
navigate_firefox_to "http://localhost:8000"
sleep 2
take_screenshot /tmp/task_initial.png