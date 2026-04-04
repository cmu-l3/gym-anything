#!/bin/bash
echo "=== Setting up Register Prohibited Software task ==="

# Source task utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure ServiceDesk Plus is running
echo "Waiting for ServiceDesk Plus..."
ensure_sdp_running

# Open Firefox to the login page
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# Record initial count of prohibited software (to detect changes)
echo "Recording initial database state..."
INITIAL_PROHIBITED_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM softwarelist sl JOIN softwaretype st ON sl.softwaretypeid = st.softwaretypeid WHERE st.typename = 'Prohibited'" 2>/dev/null || echo "0")
echo "$INITIAL_PROHIBITED_COUNT" > /tmp/initial_prohibited_count.txt

# Take initial screenshot
echo "Capturing initial state..."
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="