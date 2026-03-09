#!/bin/bash
# Setup for "create_custom_request_view" task

echo "=== Setting up Create Custom Request View task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure SDP is running (waits for install if needed)
ensure_sdp_running

# 2. Clean up: Remove the view if it already exists from a previous run
# This ensures we aren't verifying an old view
log "Cleaning up any existing view with the target name..."
sdp_db_exec "DELETE FROM ViewCriteria WHERE VIEWID IN (SELECT VIEWID FROM ViewConfiguration WHERE VIEWNAME = 'Critical Unassigned Triage');"
sdp_db_exec "DELETE FROM ViewConfiguration WHERE VIEWNAME = 'Critical Unassigned Triage';"

# 3. Record start time
date +%s > /tmp/task_start_time.txt

# 4. Open Firefox to the Requests list
# We use the generic WorkOrder URL which usually lists requests
TARGET_URL="${SDP_BASE_URL}/ManageEngine/WorkOrder.do?module=Request"
ensure_firefox_on_sdp "$TARGET_URL"

# 5. Maximize and focus
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 6. Initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="