#!/bin/bash
echo "=== Setting up create_revenue_recognition_plan task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up/Reset State
# Deactivate any existing rules with the specific name to allow a fresh creation test
# We use the GardenWorld Client ID (typically 11)
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    CLIENT_ID=11
fi

echo "--- Cleaning up previous test data (Client $CLIENT_ID) ---"
idempiere_query "UPDATE C_RevenueRecognition SET IsActive='N', Name=Name||'_OLD_'||to_char(now(), 'YYYYMMDDHH24MISS') WHERE Name='12 Month Subscription' AND AD_Client_ID=$CLIENT_ID" 2>/dev/null || true

# 2. Record initial count for verification
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM C_RevenueRecognition WHERE AD_Client_ID=$CLIENT_ID AND IsActive='Y'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial Revenue Recognition Rules count: $INITIAL_COUNT"

# 3. Ensure Firefox is running and at Dashboard
echo "--- Ensuring iDempiere is ready ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard to ensure clean starting state
# This function handles the ZK "Leave Page?" dialog if strictly necessary, 
# though usually dashboard navigation is safe.
navigate_to_dashboard

# Maximize window for better agent visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="