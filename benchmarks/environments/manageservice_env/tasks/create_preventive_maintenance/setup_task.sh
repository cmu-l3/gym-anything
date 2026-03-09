#!/bin/bash
# Setup script for create_preventive_maintenance task
# - Ensures ServiceDesk Plus is running
# - Records initial PM task count for anti-gaming verification
# - Opens Firefox to the Dashboard

echo "=== Setting up Create Preventive Maintenance Task ==="

# Source task utilities for SDP interactions
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure SDP is running (waits for install if needed)
ensure_sdp_running

# 2. Record initial Preventive Maintenance task count
# We try 'preventivemaintenance' table. If it doesn't exist, we assume 0.
echo "Recording initial PM count..."
INITIAL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM preventivemaintenance" 2>/dev/null || echo "0")
# If the previous command failed (returned empty or error text), default to 0
if ! [[ "$INITIAL_COUNT" =~ ^[0-9]+$ ]]; then
    INITIAL_COUNT=0
fi
echo "$INITIAL_COUNT" > /tmp/initial_pm_count.txt
echo "Initial PM count: $INITIAL_COUNT"

# 3. Launch Firefox to the main dashboard
# The agent needs to navigate to Admin/PM from here
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/HomePage.do"
sleep 5

# 4. Maximize window and take initial screenshot
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="