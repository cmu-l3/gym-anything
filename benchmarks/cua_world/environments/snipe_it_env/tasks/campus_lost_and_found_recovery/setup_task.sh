#!/bin/bash
echo "=== Setting up campus_lost_and_found_recovery task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

get_id() {
    echo "$1" | jq -r '.payload.id // .id // empty' 2>/dev/null
}

# ---------------------------------------------------------------
# 1. Clean up potential old task state
# ---------------------------------------------------------------
echo "Cleaning up any existing entities for this task..."
snipeit_db_query "DELETE FROM locations WHERE name='Security Holding'"
snipeit_db_query "DELETE FROM status_labels WHERE name='Recovered - Holding'"
snipeit_db_query "DELETE FROM assets WHERE serial IN ('SNDELL-992211', 'SNAPPLE-445566', 'SNPOLY-778899')"

# ---------------------------------------------------------------
# 2. Get dependencies to inject assets
# ---------------------------------------------------------------
echo "Retrieving system dependencies..."
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
MDL_LAPTOP=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%Latitude%' OR name LIKE '%OptiPlex%' LIMIT 1" | tr -d '[:space:]')
MDL_TABLET=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%iPad%' OR name LIKE '%Tablet%' LIMIT 1" | tr -d '[:space:]')
MDL_PHONE=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%Poly%' OR name LIKE '%Phone%' LIMIT 1" | tr -d '[:space:]')

# Fallbacks if specific models aren't found
if [ -z "$MDL_LAPTOP" ]; then MDL_LAPTOP=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]'); fi
if [ -z "$MDL_TABLET" ]; then MDL_TABLET=$MDL_LAPTOP; fi
if [ -z "$MDL_PHONE" ]; then MDL_PHONE=$MDL_LAPTOP; fi

TARGET_USER=$(snipeit_db_query "SELECT id FROM users WHERE username != 'admin' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
TARGET_LOC=$(snipeit_db_query "SELECT id FROM locations LIMIT 1" | tr -d '[:space:]')

# ---------------------------------------------------------------
# 3. Inject the three recovered assets
# ---------------------------------------------------------------
echo "Injecting target assets..."

# Device 1: Checked out to a user
A1_ID=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-LF01\",\"name\":\"Dell XPS 15\",\"model_id\":$MDL_LAPTOP,\"status_id\":$SL_READY,\"serial\":\"SNDELL-992211\"}")")
if [ -n "$A1_ID" ]; then
    snipeit_api POST "hardware/${A1_ID}/checkout" "{\"assigned_user\":$TARGET_USER,\"checkout_to_type\":\"user\"}" > /dev/null
    echo "  Device 1 (SNDELL-992211) created and checked out to user $TARGET_USER"
fi

# Device 2: Ready to Deploy (unassigned)
A2_ID=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-LF02\",\"name\":\"iPad Pro\",\"model_id\":$MDL_TABLET,\"status_id\":$SL_READY,\"serial\":\"SNAPPLE-445566\"}")")
if [ -n "$A2_ID" ]; then
    echo "  Device 2 (SNAPPLE-445566) created (Unassigned)"
fi

# Device 3: Checked out to a location
A3_ID=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-LF03\",\"name\":\"Polycom Conference\",\"model_id\":$MDL_PHONE,\"status_id\":$SL_READY,\"serial\":\"SNPOLY-778899\"}")")
if [ -n "$A3_ID" ]; then
    snipeit_api POST "hardware/${A3_ID}/checkout" "{\"assigned_location\":$TARGET_LOC,\"checkout_to_type\":\"location\"}" > /dev/null
    echo "  Device 3 (SNPOLY-778899) created and checked out to location $TARGET_LOC"
fi

# Save the exact IDs injected so we can verify the agent didn't delete and recreate them
echo "$A1_ID" > /tmp/lf_a1_id.txt
echo "$A2_ID" > /tmp/lf_a2_id.txt
echo "$A3_ID" > /tmp/lf_a3_id.txt

# Record baseline counts for anti-gaming
get_asset_count > /tmp/lf_initial_asset_count.txt
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 4. Open UI
# ---------------------------------------------------------------
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="