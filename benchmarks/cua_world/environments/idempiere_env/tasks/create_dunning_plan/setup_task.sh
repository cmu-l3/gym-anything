#!/bin/bash
set -e
echo "=== Setting up create_dunning_plan task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Clean up any pre-existing Dunning Plan with the target name
# We delete by name to ensure the agent starts fresh
echo "--- Cleaning up previous data ---"
CLIENT_ID=$(get_gardenworld_client_id)
TARGET_NAME="Standard Collections"

if [ -n "$CLIENT_ID" ]; then
    # Get ID if exists
    EXISTING_ID=$(idempiere_query "SELECT c_dunning_id FROM c_dunning WHERE name='$TARGET_NAME' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "0" ]; then
        echo "  Found existing plan ID $EXISTING_ID - Deleting..."
        # Delete levels first (foreign key constraint)
        idempiere_query "DELETE FROM c_dunninglevel WHERE c_dunning_id=$EXISTING_ID" 2>/dev/null || true
        # Delete header
        idempiere_query "DELETE FROM c_dunning WHERE c_dunning_id=$EXISTING_ID" 2>/dev/null || true
    else
        echo "  No existing plan found."
    fi
else
    echo "  WARNING: Could not determine Client ID."
fi

# 2. Record initial count of dunning plans (for anti-gaming)
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_dunning WHERE ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_dunning_count.txt
echo "  Initial dunning plan count: $INITIAL_COUNT"

# 3. Ensure Firefox is running and navigate to iDempiere dashboard
echo "--- Navigating to iDempiere ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to iDempiere dashboard (handles ZK leave-page dialog automatically)
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "  Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="