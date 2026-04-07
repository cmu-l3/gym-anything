#!/bin/bash
set -e
echo "=== Setting up create_account_element task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any pre-existing account 76500 to ensure a clean state
echo "--- Cleaning up pre-existing data ---"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -n "$CLIENT_ID" ]; then
    # Check if exists
    COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_elementvalue WHERE value='76500' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
    if [ "$COUNT" -gt 0 ]; then
        echo "  Removing existing account 76500..."
        # Try delete; if FK constraint fails, rename it (append timestamp) to get it out of the way
        idempiere_query "DELETE FROM c_elementvalue WHERE value='76500' AND ad_client_id=$CLIENT_ID" 2>/dev/null || \
        idempiere_query "UPDATE c_elementvalue SET value='76500_' || extract(epoch from now())::int, isactive='N' WHERE value='76500' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
    fi
fi

# 2. Record initial count of element values (for tracking changes)
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_elementvalue WHERE ad_client_id=${CLIENT_ID:-11} AND isactive='Y'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_element_count.txt
echo "  Initial element value count: $INITIAL_COUNT"

# 3. Ensure Firefox is running and navigate to iDempiere dashboard
echo "--- Navigating to iDempiere dashboard ---"
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