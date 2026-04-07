#!/bin/bash
set -e
echo "=== Setting up BOM Creation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Verify and Cleanup Data
# ---------------------------------------------------------------
echo "--- Verifying prerequisite products ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    CLIENT_ID="11" # Default to GardenWorld if query fails
fi
echo "GardenWorld Client ID: $CLIENT_ID"

# Clean up any existing BOM with the same search key (ensure clean state)
echo "--- Cleaning up any pre-existing BOM with search key PS-BOM-2024 ---"
EXISTING_BOM_ID=$(idempiere_query "SELECT pp_product_bom_id FROM pp_product_bom WHERE value='PS-BOM-2024' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "")

if [ -n "$EXISTING_BOM_ID" ] && [ "$EXISTING_BOM_ID" != "" ]; then
    echo "  Removing existing BOM lines for BOM ID: $EXISTING_BOM_ID"
    idempiere_query "DELETE FROM pp_product_bomline WHERE pp_product_bom_id=$EXISTING_BOM_ID" 2>/dev/null || true
    echo "  Removing existing BOM header: $EXISTING_BOM_ID"
    idempiere_query "DELETE FROM pp_product_bom WHERE pp_product_bom_id=$EXISTING_BOM_ID" 2>/dev/null || true
fi

# Record initial BOM count
INITIAL_BOM_COUNT=$(idempiere_query "SELECT COUNT(*) FROM pp_product_bom WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_BOM_COUNT" > /tmp/initial_bom_count.txt
echo "Initial BOM count: $INITIAL_BOM_COUNT"

# ---------------------------------------------------------------
# 2. Ensure Application is Ready
# ---------------------------------------------------------------
echo "--- Ensuring iDempiere is accessible ---"
ensure_idempiere_open ""
sleep 5

# Maximize Firefox window explicitly
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# ---------------------------------------------------------------
# 3. Capture Initial Evidence
# ---------------------------------------------------------------
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved"

echo "=== BOM Creation Task Setup Complete ==="