#!/bin/bash
set -e
echo "=== Setting up Create Custom CI Type task ==="

# Source task utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure ServiceDesk Plus is running (waits for install if needed)
ensure_sdp_running

# 2. Clean up any existing "Delivery Drone" CI Type to ensure a fair test
#    We delete from the DB directly to reset state.
echo "Cleaning up any previous 'Delivery Drone' CI types..."
sdp_db_exec "DELETE FROM citype_attributes_map WHERE citypeid IN (SELECT citypeid FROM citype WHERE citypename = 'Delivery Drone');"
sdp_db_exec "DELETE FROM citype WHERE citypename = 'Delivery Drone';"

# 3. Launch Firefox pointing to the login page
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# 4. Wait a moment for UI to be ready and take initial screenshot
sleep 5
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="