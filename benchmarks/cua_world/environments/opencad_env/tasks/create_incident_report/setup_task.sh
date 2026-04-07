#!/bin/bash
echo "=== Setting up create_incident_report task ==="

source /workspace/scripts/task_utils.sh

# Record initial report count (if table exists)
INITIAL_REPORT_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM reports" 2>/dev/null || echo "0")
echo "$INITIAL_REPORT_COUNT" | sudo tee /tmp/initial_report_count > /dev/null
sudo chmod 666 /tmp/initial_report_count

# Record max report ID to filter for NEW reports only
# We check common table names for reports just in case
MAX_REPORT_ID=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM reports" 2>/dev/null || echo "0")
echo "$MAX_REPORT_ID" | sudo tee /tmp/baseline_max_report_id > /dev/null
sudo chmod 666 /tmp/baseline_max_report_id

# Remove Firefox profile locks and relaunch to ensure clean state
rm -f /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to the login page
DISPLAY=:1 firefox "http://localhost/index.php" &
sleep 10

# Dismiss any Firefox first-run popups
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="