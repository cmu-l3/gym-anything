#!/bin/bash
set -e
echo "=== Setting up Configure Request Archiving Policy task ==="

# Source task utilities for SDP interaction
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure SDP is running (waits for install if needed)
ensure_sdp_running

# 2. Reset Archiving Configuration to KNOWN BAD STATE (Disabled, 1000 days)
# This ensures we can detect if the agent actually changes it.
echo "Resetting archiving configuration..."

# Try resetting via main table structure (Request module_id is typically 1 or found via query)
# status: false (disabled), no_of_days: 1000
sdp_db_exec "UPDATE archive_config SET status = false, no_of_days = 1000 WHERE module_id = (SELECT module_id FROM module WHERE module_name = 'Request');" || true

# Also try legacy/alternate table name just in case
sdp_db_exec "UPDATE archiveconfiguration SET enabled = false, days = 1000 WHERE module = 'Request';" 2>/dev/null || true

# 3. Launch Firefox to the Login page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 4. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="