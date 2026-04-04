#!/bin/bash
echo "=== Setting up Create Work Log Type task ==="

# Source SDP utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure SDP is running
ensure_sdp_running

# Clean up any existing "On-Site Repair" type to ensure a clean state
log "Cleaning up old data..."
sdp_db_exec "DELETE FROM worklogtype WHERE name = 'On-Site Repair';"
sdp_db_exec "DELETE FROM worklogtype WHERE name = 'On-Site Repair';" # Run twice just in case of dependencies

# Record initial count of work log types
INITIAL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM worklogtype;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_wlt_count.txt

# Open Firefox to the login page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# Wait a moment for window to settle
sleep 5

# Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Create Work Log Type 'On-Site Repair' ($150/hr)"