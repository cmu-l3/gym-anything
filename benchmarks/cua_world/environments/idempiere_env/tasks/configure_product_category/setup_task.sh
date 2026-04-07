#!/bin/bash
set -e
echo "=== Setting up Configure Product Category Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up: Remove the category if it exists from a previous run to ensure a clean state
# We also revert Patio Chair to 'Standard' category if needed
echo "--- Preparing Database State ---"

# Get Client ID (GardenWorld)
CLIENT_ID=$(get_gardenworld_client_id)

# Find ID of "Standard" category (default in GardenWorld)
STD_CAT_ID=$(idempiere_query "SELECT m_product_category_id FROM m_product_category WHERE name='Standard' AND ad_client_id=$CLIENT_ID LIMIT 1")

# Revert Patio Chair to Standard category if it was moved
if [ -n "$STD_CAT_ID" ]; then
    idempiere_query "UPDATE m_product SET m_product_category_id=$STD_CAT_ID WHERE name='Patio Chair' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
fi

# Deactivate/Rename old test category to avoid conflicts
idempiere_query "UPDATE m_product_category SET isactive='N', value=value||'_OLD_'||to_char(now(),'Ms') WHERE value='OUTDOOR-FURN' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true

# Record initial state of Patio Chair
INITIAL_CAT_ID=$(idempiere_query "SELECT m_product_category_id FROM m_product WHERE name='Patio Chair' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_CAT_ID" > /tmp/initial_product_cat_id.txt
echo "Initial Category ID for Patio Chair: $INITIAL_CAT_ID"

# 2. Ensure Firefox is running and iDempiere is loaded
echo "--- Checking Application State ---"
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Ensure we are at the dashboard
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="