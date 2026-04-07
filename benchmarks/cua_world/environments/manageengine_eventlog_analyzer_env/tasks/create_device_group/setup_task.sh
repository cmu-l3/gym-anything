#!/bin/bash
# Setup script for create_device_group task

echo "=== Setting up Create Device Group Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || { echo "Failed to source task_utils"; exit 1; }

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Wait for EventLog Analyzer to be fully ready
wait_for_eventlog_analyzer 900

# Record initial device group state for anti-gaming comparison
# We record the count and the list of names to ensure the new group is actually new
echo "Recording initial device group state..."
INITIAL_COUNT=$(ela_db_query "SELECT count(*) FROM hostgroup" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_group_count.txt

ela_db_query "SELECT groupname FROM hostgroup" > /tmp/initial_groups.txt 2>/dev/null || true

echo "Initial group count: $INITIAL_COUNT"

# Ensure Firefox is open on EventLog Analyzer Dashboard
# This puts the agent in a known state but not immediately at the settings page
ensure_firefox_on_ela "/event/index.do"
sleep 5

# Dismiss any popup dialogs that might block the view
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="