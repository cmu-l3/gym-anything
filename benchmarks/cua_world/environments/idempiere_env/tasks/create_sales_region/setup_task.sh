#!/bin/bash
set -e
echo "=== Setting up create_sales_region task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ----------------------------------------------------------------
# 1. Clean up Environment (Idempotency)
# ----------------------------------------------------------------
echo "--- Cleaning up previous state ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    CLIENT_ID=11
    echo "  Defaulting Client ID to 11"
fi

# Reset Joe Block's region to NULL
# Note: C_SalesRegion_ID is the foreign key in C_BPartner
idempiere_query "UPDATE c_bpartner SET c_salesregion_id=NULL WHERE name='Joe Block' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true

# Deactivate/Rename any existing 'PNW' region to avoid conflicts
# We append a timestamp to the value to effectively "delete" it from the agent's view
TS=$(date +%s)
idempiere_query "UPDATE c_salesregion SET value='PNW_OLD_$TS', isactive='N' WHERE value='PNW' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true

echo "  Cleanup complete."

# ----------------------------------------------------------------
# 2. Record Initial State
# ----------------------------------------------------------------
# Count existing regions (should be 0 for PNW now)
INITIAL_REGION_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_salesregion WHERE value='PNW' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_REGION_COUNT" > /tmp/initial_region_count.txt

# ----------------------------------------------------------------
# 3. Prepare Application
# ----------------------------------------------------------------
echo "--- Ensuring iDempiere is ready ---"

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -iq "firefox\|mozilla"; then
            break
        fi
        sleep 1
    done
    sleep 10
fi

# Navigate to Dashboard to start clean
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="