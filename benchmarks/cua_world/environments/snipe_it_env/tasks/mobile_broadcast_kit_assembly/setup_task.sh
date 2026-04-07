#!/bin/bash
echo "=== Setting up mobile_broadcast_kit_assembly task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Helper to extract ID from API response
get_id() {
    echo "$1" | jq -r '.payload.id // .id // empty' 2>/dev/null
}

echo "--- Fetching status labels ---"
SL_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
SL_REPAIR_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Out for Repair' LIMIT 1" | tr -d '[:space:]')
echo "Ready ID: $SL_READY_ID | Repair ID: $SL_REPAIR_ID"

echo "--- Creating users ---"
for u in "Elena Rostova erostova" "Marcus Johnson mjohnson" "Sarah Chen schen"; do
    fn=$(echo "$u" | awk '{print $1}')
    ln=$(echo "$u" | awk '{print $2}')
    un=$(echo "$u" | awk '{print $3}')
    snipeit_api POST "users" "{\"first_name\":\"$fn\",\"last_name\":\"$ln\",\"username\":\"$un\",\"password\":\"password123\",\"email\":\"$un@example.com\",\"activated\":1}" > /dev/null
done

echo "--- Creating categories & models ---"
CAT_CAM=$(get_id "$(snipeit_api POST "categories" '{"name":"Cameras","category_type":"asset"}')")
CAT_PERIPH=$(get_id "$(snipeit_api POST "categories" '{"name":"Peripherals","category_type":"asset"}')")

MOD_CAM=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Sony FX6\",\"category_id\":$CAT_CAM}")")
MOD_LENS=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Sony 24-70mm G-Master\",\"category_id\":$CAT_PERIPH}")")
MOD_MIC=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Sennheiser EW-DP\",\"category_id\":$CAT_PERIPH}")")
MOD_BAT=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Anton Bauer Titon 90\",\"category_id\":$CAT_PERIPH}")")

echo "--- Creating assets ---"
# Cameras
for i in 1 2 3; do 
    snipeit_api POST "hardware" "{\"asset_tag\":\"CAM-00$i\",\"name\":\"Sony FX6 Camera Body $i\",\"model_id\":$MOD_CAM,\"status_id\":$SL_READY_ID}" > /dev/null
done

# Lenses
for i in 1 2 3; do 
    snipeit_api POST "hardware" "{\"asset_tag\":\"LENS-00$i\",\"model_id\":$MOD_LENS,\"status_id\":$SL_READY_ID}" > /dev/null
done

# Batteries
for i in 1 2 3; do 
    snipeit_api POST "hardware" "{\"asset_tag\":\"BAT-00$i\",\"model_id\":$MOD_BAT,\"status_id\":$SL_READY_ID}" > /dev/null
done

# Microphones (1,2,4 are good. 3 is broken)
for i in 1 2 4; do 
    snipeit_api POST "hardware" "{\"asset_tag\":\"MIC-00$i\",\"model_id\":$MOD_MIC,\"status_id\":$SL_READY_ID}" > /dev/null
done
snipeit_api POST "hardware" "{\"asset_tag\":\"MIC-003\",\"name\":\"Broken Mic\",\"model_id\":$MOD_MIC,\"status_id\":$SL_REPAIR_ID,\"notes\":\"Connector damaged - Do not deploy\"}" > /dev/null

sleep 2

echo "--- Launching UI ---"
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/hardware"
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="