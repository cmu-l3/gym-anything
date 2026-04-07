#!/bin/bash
echo "=== Setting up add_street task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial street count
INITIAL_STREET_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM streets")
echo "${INITIAL_STREET_COUNT:-0}" | sudo tee /tmp/initial_street_count > /dev/null
sudo chmod 666 /tmp/initial_street_count

# Record max street ID to filter for new records later
MAX_STREET_ID=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM streets")
echo "${MAX_STREET_ID:-0}" | sudo tee /tmp/baseline_max_street_id > /dev/null
sudo chmod 666 /tmp/baseline_max_street_id

# Verify the target street doesn't already exist (anti-gaming)
EXISTING_CHECK=$(opencad_db_query "SELECT id FROM streets WHERE LOWER(name) LIKE '%quarry%ridge%' LIMIT 1")
if [ -n "$EXISTING_CHECK" ]; then
    echo "WARNING: Target street already exists. Attempting to clean up..."
    opencad_db_query "DELETE FROM streets WHERE id = ${EXISTING_CHECK}"
fi

# Remove Firefox profile locks and relaunch to login page
rm -f /home/ga/.mozilla/firefox/default-release/lock /home/ga/.mozilla/firefox/default-release/.parentlock 2>/dev/null || true
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock /home/ga/snap/firefox/common/.mozilla/firefox/*/.parentlock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
DISPLAY=:1 firefox "http://localhost/index.php" &
sleep 10

# Dismiss Firefox popups/restore session dialogs
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