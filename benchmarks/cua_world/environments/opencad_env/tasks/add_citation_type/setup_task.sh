#!/bin/bash
echo "=== Setting up add_citation_type task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs: Delete 'Equipment Safety Violation' if it exists
echo "Cleaning up existing target data..."
opencad_db_query "DELETE FROM citation_types WHERE LOWER(citation_type) LIKE '%equipment safety violation%'" 2>/dev/null || true

# Record initial citation type count (after cleanup)
INITIAL_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM citation_types")
echo "${INITIAL_COUNT:-0}" | sudo tee /tmp/initial_citation_type_count > /dev/null
sudo chmod 666 /tmp/initial_citation_type_count
echo "Initial citation type count: ${INITIAL_COUNT:-0}"

# Record max ID to filter for new records later
MAX_ID=$(opencad_db_query "SELECT COALESCE(MAX(id), 0) FROM citation_types")
echo "${MAX_ID:-0}" | sudo tee /tmp/initial_max_id > /dev/null
sudo chmod 666 /tmp/initial_max_id

# Ensure Firefox is fresh
rm -f /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to Login Page
echo "Launching Firefox..."
DISPLAY=:1 firefox "http://localhost/login.php" &
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

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="