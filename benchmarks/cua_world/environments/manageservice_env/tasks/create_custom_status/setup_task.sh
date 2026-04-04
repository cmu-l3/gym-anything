#!/bin/bash
set -e
echo "=== Setting up Create Custom Status task ==="

# Source utilities for SDP interaction
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure ServiceDesk Plus is running
ensure_sdp_running

# 1. Clean Slate: Remove the status if it already exists to ensure the agent actually creates it
echo "Ensuring target status does not exist..."
sdp_db_exec "DELETE FROM statusdefinition WHERE LOWER(statusname) = 'waiting for vendor';"

# 2. Record Initial State: Get max status ID to verify new creation later
INITIAL_MAX_ID=$(sdp_db_exec "SELECT COALESCE(MAX(statusid), 0) FROM statusdefinition;")
echo "$INITIAL_MAX_ID" > /tmp/initial_status_max_id.txt
echo "Initial Max Status ID: $INITIAL_MAX_ID"

# 3. Open Firefox to SDP Login
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create 'Waiting for Vendor' status with type 'Pending'"