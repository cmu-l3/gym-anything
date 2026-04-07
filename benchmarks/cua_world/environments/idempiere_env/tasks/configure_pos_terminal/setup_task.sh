#!/bin/bash
set -e
echo "=== Setting up configure_pos_terminal task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Cleanup: Remove any existing POS terminal with the target name to ensure a clean start
echo "--- Cleaning up pre-existing data ---"
CLIENT_ID=$(get_gardenworld_client_id)
# Default to 11 if not found
CLIENT_ID=${CLIENT_ID:-11}

# Delete existing record if it exists
idempiere_query "DELETE FROM C_POS WHERE Name='Express Lane 1' AND AD_Client_ID=$CLIENT_ID" 2>/dev/null || true

# 2. Record initial count for anti-gaming
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM C_POS WHERE AD_Client_ID=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_pos_count.txt
echo "Initial POS Terminal count: $INITIAL_COUNT"

# 3. Ensure iDempiere is running and reachable
echo "--- Checking iDempiere status ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    # Wait for startup
    sleep 15
fi

# 4. Navigate to dashboard to ensure known starting state
navigate_to_dashboard

# 5. Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 6. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="