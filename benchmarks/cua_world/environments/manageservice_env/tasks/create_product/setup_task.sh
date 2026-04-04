#!/bin/bash
set -e
echo "=== Setting up Create Product task ==="

# Source common utilities
source /workspace/scripts/task_utils.sh

# Record task start time (seconds and milliseconds)
date +%s > /tmp/task_start_time.txt
# Current time in millis for DB comparison (SDP uses millis often)
echo $(($(date +%s) * 1000)) > /tmp/task_start_time_ms.txt

# Ensure SDP is running
ensure_sdp_running

# Clear mandatory password change if set
clear_mandatory_password_change

# Clean up existing data to ensure fresh start
# Note: Delete product first to avoid FK constraint issues
log "Cleaning up existing 'Network Switch' and 'Cisco Catalyst' data..."

# Try to delete existing product if it matches our target name
sdp_db_exec "DELETE FROM product WHERE productname ILIKE '%Cisco Catalyst 9200L-24P-4G%';" 2>/dev/null || true

# Try to delete existing product type if it matches our target name
# Note: This might fail if other products depend on it, but for a fresh task it should be clean
sdp_db_exec "DELETE FROM producttype WHERE name ILIKE 'Network Switch' OR typename ILIKE 'Network Switch';" 2>/dev/null || true

# Launch Firefox to SDP login page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="