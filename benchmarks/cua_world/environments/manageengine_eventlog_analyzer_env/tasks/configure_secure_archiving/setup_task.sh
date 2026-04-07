#!/bin/bash
echo "=== Setting up Configure Secure Archiving task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# Record initial database state (specifically look for archive settings)
# We capture relevant config rows to prove they change later
echo "Recording initial DB state..."
ela-db-query "SELECT * FROM GlobalConfig WHERE category='Archive' OR paramname LIKE '%ARCHIVE%'" > /tmp/initial_db_state.txt 2>/dev/null || true
ela-db-query "SELECT * FROM SystemSettings" >> /tmp/initial_db_state.txt 2>/dev/null || true

# Navigate Firefox to the Settings/Admin dashboard
# We don't go directly to Archive settings to force the agent to find it
ensure_firefox_on_ela "/event/AppsHome.do#/settings/admin"
sleep 5

# Dismiss any popup dialogs/wizards
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape
sleep 1

# Maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    maximize_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="