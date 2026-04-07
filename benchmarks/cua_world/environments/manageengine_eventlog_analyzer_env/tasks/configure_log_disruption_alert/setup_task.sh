#!/bin/bash
echo "=== Setting up Configure Log Disruption Alert task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# Record initial DB state (to detect changes)
# We try to grab the SystemAlertConfig table if it exists
echo "Recording initial database state..."
ela_db_query "SELECT * FROM SystemAlertConfig" > /tmp/initial_alert_config.txt 2>/dev/null || \
ela_db_query "SELECT * FROM AlertProfile" > /tmp/initial_alert_config.txt 2>/dev/null || true

# Open Firefox to the main dashboard (neutral starting point)
# We don't want to open directly to the settings page; the agent must find it.
ensure_firefox_on_ela "/event/index.do"
sleep 5

# Maximize Firefox
WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any popup dialogs
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="