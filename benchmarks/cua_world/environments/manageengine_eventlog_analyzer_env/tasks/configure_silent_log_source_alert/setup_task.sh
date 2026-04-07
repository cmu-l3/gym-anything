#!/bin/bash
# Setup for "configure_silent_log_source_alert" task

echo "=== Setting up Configure Silent Log Source Alert task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# Clean up any previous alert profile with the target name to ensure fresh creation
echo "Cleaning up old alert profiles..."
ela_db_query "DELETE FROM AlertProfile WHERE PROFILE_NAME = 'Critical_Log_Gap_Alert';" 2>/dev/null || true
ela_db_query "DELETE FROM LAAlertProfile WHERE PROFILE_NAME = 'Critical_Log_Gap_Alert';" 2>/dev/null || true

# Navigate Firefox to EventLog Analyzer Alerts/Settings section
# Using the Alerts tab directly is usually a good starting point
ensure_firefox_on_ela "/event/AppsHome.do#/alerts/alert"
sleep 5

# Dismiss any popups (e.g., 'What's New')
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "EventLog Analyzer is ready."
echo "Please configure the 'Critical_Log_Gap_Alert' as described."