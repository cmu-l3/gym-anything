#!/bin/bash
echo "=== Setting up self_service_portal_catalog task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Helper to extract ID from API response
get_id() {
    echo "$1" | jq -r '.payload.id // .id // empty' 2>/dev/null
}

echo "--- Injecting target locations ---"
# Create Locations
LOC_MAIN=$(get_id "$(snipeit_api POST "locations" '{"name":"Main Storage","city":"HQ","address":"Floor 1"}')")
LOC_HELP=$(get_id "$(snipeit_api POST "locations" '{"name":"IT Helpdesk - Walk-up","city":"HQ","address":"Floor 2"}')")

# If API fails for some reason, fallback to DB search
if [ -z "$LOC_MAIN" ]; then LOC_MAIN=$(snipeit_db_query "SELECT id FROM locations LIMIT 1" | tr -d '[:space:]'); fi
if [ -z "$LOC_HELP" ]; then LOC_HELP=$(snipeit_db_query "SELECT id FROM locations ORDER BY id DESC LIMIT 1" | tr -d '[:space:]'); fi

echo "--- Preparing Categories and Manufacturers ---"
CAT_LAPTOP=$(snipeit_db_query "SELECT id FROM categories WHERE name='Laptops' LIMIT 1" | tr -d '[:space:]')
CAT_MONITOR=$(snipeit_db_query "SELECT id FROM categories WHERE name='Monitors' LIMIT 1" | tr -d '[:space:]')
CAT_ACC=$(get_id "$(snipeit_api POST "categories" '{"name":"Accessories","category_type":"asset"}')")

MFG_APPLE=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Apple' LIMIT 1" | tr -d '[:space:]')
MFG_DELL=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Dell' LIMIT 1" | tr -d '[:space:]')
MFG_LENOVO=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Lenovo' LIMIT 1" | tr -d '[:space:]')
MFG_LOGI=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"Logitech"}')")

# Ensure fallbacks if any is empty
[ -z "$CAT_ACC" ] && CAT_ACC=$CAT_MONITOR
[ -z "$MFG_LOGI" ] && MFG_LOGI=$MFG_DELL
[ -z "$MFG_APPLE" ] && MFG_APPLE=$MFG_DELL
[ -z "$MFG_LENOVO" ] && MFG_LENOVO=$MFG_DELL
[ -z "$CAT_LAPTOP" ] && CAT_LAPTOP=$CAT_MONITOR

echo "--- Injecting Models ---"
# 1. Dell Monitor - Not Requestable (Target: make requestable)
MDL_DELL_MON=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Dell U2723QE Monitor\",\"category_id\":$CAT_MONITOR,\"manufacturer_id\":$MFG_DELL,\"requestable\":0}")")

# 2. Logitech Mouse - Not Requestable (Target: make requestable)
MDL_LOGI_MOUSE=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Logitech MX Master 3S\",\"category_id\":$CAT_ACC,\"manufacturer_id\":$MFG_LOGI,\"requestable\":0}")")

# 3. MacBook Pro - Requestable (Target: make NOT requestable)
MDL_MAC=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Apple MacBook Pro 16 M3 Max\",\"category_id\":$CAT_LAPTOP,\"manufacturer_id\":$MFG_APPLE,\"requestable\":1}")")

# 4. Lenovo ThinkPad - Not Requestable
MDL_T14=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Lenovo ThinkPad T14 Gen 4\",\"category_id\":$CAT_LAPTOP,\"manufacturer_id\":$MFG_LENOVO,\"requestable\":0}")")


echo "--- Injecting Hardware Assets ---"
STAT_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# Three Loaners (Target: Requestable + IT Helpdesk Location)
for i in 1 2 3; do
    snipeit_api POST "hardware" "{\"asset_tag\":\"LOANER-T14-0$i\",\"name\":\"Standard Loaner Pool\",\"status_id\":$STAT_READY,\"model_id\":$MDL_T14,\"rtd_location_id\":$LOC_MAIN,\"requestable\":0}"
done

# Two Executives (Target: Do not touch)
for i in 1 2; do
    snipeit_api POST "hardware" "{\"asset_tag\":\"EXEC-T14-0$i\",\"name\":\"Executive Assigned Setup\",\"status_id\":$STAT_READY,\"model_id\":$MDL_T14,\"rtd_location_id\":$LOC_MAIN,\"requestable\":0}"
done

sleep 2

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt

echo "--- Launching Application ---"
# Ensure Firefox is running and on Snipe-IT
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== self_service_portal_catalog task setup complete ==="