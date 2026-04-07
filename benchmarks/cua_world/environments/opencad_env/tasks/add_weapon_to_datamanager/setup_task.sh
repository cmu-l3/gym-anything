#!/bin/bash
echo "=== Setting up add_weapon_to_datamanager task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Record initial weapon count
# We assume the table is named 'weapons' based on OpenCAD schema conventions
INITIAL_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM weapons" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" | sudo tee /tmp/initial_weapon_count > /dev/null
sudo chmod 666 /tmp/initial_weapon_count

# Record max ID to distinguish new records
MAX_ID=$(opencad_db_query "SELECT COALESCE(MAX(weapon_id), MAX(id), 0) FROM weapons" 2>/dev/null)
echo "${MAX_ID:-0}" | sudo tee /tmp/baseline_max_weapon_id > /dev/null
sudo chmod 666 /tmp/baseline_max_weapon_id

# Remove Firefox profile locks (both regular and snap) and relaunch to ensure clean state
rm -f /home/ga/.mozilla/firefox/default-release/lock /home/ga/.mozilla/firefox/default-release/.parentlock 2>/dev/null || true
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock /home/ga/snap/firefox/common/.mozilla/firefox/*/.parentlock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Start Firefox at the login page
DISPLAY=:1 firefox "http://localhost/index.php" &
sleep 10

# Dismiss Firefox popups/restore session dialogs
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize the browser window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="