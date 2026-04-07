#!/bin/bash
echo "=== Setting up dispatch_new_incident_type task ==="

source /workspace/scripts/task_utils.sh

# Record initial counts to detect changes
INITIAL_TYPE_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM incident_types")
INITIAL_CALL_COUNT=$(get_call_count)

echo "$INITIAL_TYPE_COUNT" | sudo tee /tmp/initial_type_count > /dev/null
echo "$INITIAL_CALL_COUNT" | sudo tee /tmp/initial_call_count > /dev/null
sudo chmod 666 /tmp/initial_type_count /tmp/initial_call_count

# Record max IDs to ensure we check new records
MAX_TYPE_ID=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM incident_types")
MAX_CALL_ID=$(opencad_db_query "SELECT COALESCE(MAX(call_id),0) FROM calls")

echo "${MAX_TYPE_ID:-0}" | sudo tee /tmp/baseline_max_type_id > /dev/null
echo "${MAX_CALL_ID:-0}" | sudo tee /tmp/baseline_max_call_id > /dev/null
sudo chmod 666 /tmp/baseline_max_type_id /tmp/baseline_max_call_id

# Remove Firefox profile locks (both regular and snap) and relaunch
rm -f /home/ga/.mozilla/firefox/default-release/lock /home/ga/.mozilla/firefox/default-release/.parentlock 2>/dev/null || true
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock /home/ga/snap/firefox/common/.mozilla/firefox/*/.parentlock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Start Firefox at login page
DISPLAY=:1 firefox "http://localhost/index.php" &
sleep 10

# Dismiss Firefox popups
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="