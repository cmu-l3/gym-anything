#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_requisition task ==="

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Verify iDempiere is accessible
echo "--- Verifying iDempiere accessibility ---"
if ! curl -k -s -f -o /dev/null https://localhost:8443/webui/; then
    echo "Waiting for iDempiere..."
    sleep 10
fi

# 3. Get GardenWorld Client ID
CLIENT_ID=$(get_gardenworld_client_id)
echo "GardenWorld Client ID: $CLIENT_ID"

# 4. Record initial requisition count
INITIAL_REQ_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_requisition WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_REQ_COUNT" > /tmp/initial_requisition_count.txt
echo "Initial requisition count: $INITIAL_REQ_COUNT"

# 5. Ensure Firefox is running and focused
echo "--- Ensuring Firefox is ready ---"
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard/home to ensure clean state
navigate_to_dashboard

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="