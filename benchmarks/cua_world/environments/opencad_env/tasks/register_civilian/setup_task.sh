#!/bin/bash
echo "=== Setting up register_civilian task ==="

source /workspace/scripts/task_utils.sh

# Record initial civilian count (ncic_names is the actual person table)
INITIAL_CIV_COUNT=$(get_civilian_count)
echo "$INITIAL_CIV_COUNT" | sudo tee /tmp/initial_civilian_count > /dev/null
sudo chmod 666 /tmp/initial_civilian_count

# Record max ncic_names ID to prevent seed data false positives
MAX_NCIC_ID=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM ncic_names")
echo "${MAX_NCIC_ID:-0}" | sudo tee /tmp/baseline_max_ncic_id > /dev/null
sudo chmod 666 /tmp/baseline_max_ncic_id

# Remove Firefox profile locks (both regular and snap) and relaunch
rm -f /home/ga/.mozilla/firefox/default-release/lock /home/ga/.mozilla/firefox/default-release/.parentlock 2>/dev/null || true
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock /home/ga/snap/firefox/common/.mozilla/firefox/*/.parentlock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2
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
