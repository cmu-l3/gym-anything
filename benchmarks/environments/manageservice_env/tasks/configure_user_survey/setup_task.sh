#!/bin/bash
# Setup for "configure_user_survey" task
# Ensures SDP is running and opens Firefox to the admin login page

echo "=== Setting up Configure User Survey task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure ServiceDesk Plus is running (waits for install if needed)
ensure_sdp_running

# Record initial state of survey tables (for anti-gaming comparison)
# We dump any table with 'survey' in the name to capture initial config
echo "Recording initial survey database state..."
sdp_db_exec "SELECT tablename FROM pg_tables WHERE tablename LIKE '%survey%'" | \
while read table; do
    echo "--- $table ---"
    sdp_db_exec "SELECT * FROM $table" 2>/dev/null || true
done > /tmp/initial_survey_db_dump.txt 2>/dev/null || true

# Launch Firefox to the Login page
# The agent needs to log in as administrator to access Admin settings
log "Opening Firefox to SDP Login..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# Wait a moment for UI to stabilize
sleep 5

# Maximize Firefox for better visibility
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Configure User Satisfaction Survey"
echo "1. Login as administrator"
echo "2. Enable survey for Closed requests"
echo "3. Add the specified questions"