#!/bin/bash
# Setup for "schedule_weekly_report" task
# Ensures SDP is running, opens Firefox to Reports module, and records initial state.

echo "=== Setting up Schedule Weekly Report task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure ServiceDesk Plus is running (waits for install if needed)
ensure_sdp_running

# 2. Record initial count of scheduled reports (Anti-gaming)
# We check the 'reportscheduletask' table (common table name in SDP versions)
echo "Recording initial schedule count..."
INITIAL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM reportscheduletask;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_schedule_count.txt
log "Initial scheduled reports count: $INITIAL_COUNT"

# 3. Open Firefox to the Reports module
# This helps the agent start in the right context
REPORT_URL="${SDP_BASE_URL}/ManageEngine/Report.do"
log "Opening Firefox to: $REPORT_URL"
ensure_firefox_on_sdp "$REPORT_URL"

# 4. Wait for UI to load and capture initial screenshot
sleep 8
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "SDP is open. Agent should now navigate to Schedule Reports."