#!/bin/bash
echo "=== Setting up add_incident_type task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean state: Ensure 'Equipment Rollover' does not exist
echo "Cleaning up any existing 'Equipment Rollover' records..."
opencad_db_query "DELETE FROM incident_types WHERE LOWER(incident_type) = 'equipment rollover'"

# 3. Record baseline metrics
# Count
INITIAL_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM incident_types")
echo "${INITIAL_COUNT:-0}" > /tmp/initial_incident_type_count.txt

# Max ID (to verify new creation)
MAX_ID=$(opencad_db_query "SELECT COALESCE(MAX(incident_type_id), 0) FROM incident_types")
echo "${MAX_ID:-0}" > /tmp/initial_max_incident_type_id.txt

echo "Baseline recorded: Count=$INITIAL_COUNT, MaxID=$MAX_ID"

# 4. Prepare Application (Firefox)
# Remove Firefox profile locks to prevent startup errors
rm -f /home/ga/.mozilla/firefox/default-release/lock /home/ga/.mozilla/firefox/default-release/.parentlock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to OpenCAD login page
echo "Launching Firefox..."
DISPLAY=:1 firefox "http://localhost/login.php" &
sleep 10

# Dismiss standard browser popups (if any)
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing Firefox window ($WID)..."
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
    sleep 1
else
    echo "WARNING: Firefox window not found"
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="