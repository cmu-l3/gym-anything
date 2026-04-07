#!/bin/bash
echo "=== Setting up create_bolo_person task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial person BOLO count
INITIAL_BOLO_COUNT=$(get_bolo_person_count)
echo "$INITIAL_BOLO_COUNT" | sudo tee /tmp/initial_bolo_count > /dev/null
sudo chmod 666 /tmp/initial_bolo_count

# Record max BOLO id to prevent seed data false positives
# We use this to only look for records created *during* the task
MAX_BOLO_ID=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM bolos_persons")
echo "${MAX_BOLO_ID:-0}" | sudo tee /tmp/baseline_max_bolo_id > /dev/null
sudo chmod 666 /tmp/baseline_max_bolo_id

# Remove Firefox profile locks (both regular and snap) and relaunch to ensure clean state
rm -f /home/ga/.mozilla/firefox/default-release/lock /home/ga/.mozilla/firefox/default-release/.parentlock 2>/dev/null || true
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock /home/ga/snap/firefox/common/.mozilla/firefox/*/.parentlock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Start Firefox at the login page
DISPLAY=:1 firefox "http://localhost/index.php" &
sleep 10

# Dismiss Firefox "Make Default" popups if they appear
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize the browser window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="