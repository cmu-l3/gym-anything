#!/bin/bash
# Setup for "configure_operational_hours" task
# 1. Ensures SDP is running
# 2. Resets Operational Hours to default (24/7) to ensure clean state
# 3. Launches Firefox to the SDP home page

echo "=== Setting up Configure Operational Hours task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for SDP
ensure_sdp_running

# 2. Reset Operational Hours to default (24/7) via Database
# This prevents "do nothing" if the state was already correct from a previous run
# We assume standard table structure for SDP (OperationalHours)
echo "Resetting operational hours to default (24/7)..."

# SQL to reset hours: Set all days to 00:00-23:59 and active
# Note: Schema varies by version, but we try standard columns.
# We silence errors in case table structure differs, but we record initial state.
RESET_SQL="UPDATE operationalhours SET start_time='00:00', end_time='23:59', is_working_day=true;"
sdp_db_exec "$RESET_SQL" > /dev/null 2>&1 || true

# Record initial state for verification baseline
echo "Recording initial operational hours state..."
INITIAL_STATE_QUERY="SELECT day_of_week, start_time, end_time, is_working_day FROM operationalhours ORDER BY day_of_week;"
sdp_db_exec "$INITIAL_STATE_QUERY" > /tmp/initial_hours_state.txt
echo "Initial state recorded:"
cat /tmp/initial_hours_state.txt

# 3. Launch Firefox
# We purposefully land on the Home page (WorkOrder.do) so the agent has to navigate to Admin
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Configure Operational Hours"
echo "Target: M-F 08:00-18:00, Sat 09:00-13:00, Sun Closed"