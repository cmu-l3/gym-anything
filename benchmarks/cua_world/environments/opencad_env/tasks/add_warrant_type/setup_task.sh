#!/bin/bash
echo "=== Setting up Add Warrant Type Task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up any previous attempts (Anti-Gaming)
# Delete 'Failure to Appear' if it already exists to ensure agent creates it
echo "Cleaning up potential pre-existing records..."
opencad_db_query "DELETE FROM warrant_types WHERE LOWER(TRIM(warrant_type)) = 'failure to appear'"

# 2. Record initial state
# Get count of warrant types
INITIAL_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM warrant_types")
echo "${INITIAL_COUNT:-0}" | sudo tee /tmp/initial_warrant_type_count > /dev/null
sudo chmod 666 /tmp/initial_warrant_type_count

# Get max ID to distinguish new records
MAX_ID=$(opencad_db_query "SELECT COALESCE(MAX(id), 0) FROM warrant_types")
echo "${MAX_ID:-0}" | sudo tee /tmp/initial_max_id > /dev/null
sudo chmod 666 /tmp/initial_max_id

# 3. Prepare Application State
# Remove Firefox profile locks to prevent "Firefox is already running" errors
rm -f /home/ga/.mozilla/firefox/default-release/lock /home/ga/.mozilla/firefox/default-release/.parentlock 2>/dev/null || true
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock /home/ga/snap/firefox/common/.mozilla/firefox/*/.parentlock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to the login page
echo "Launching Firefox..."
DISPLAY=:1 firefox "http://localhost/login.php" &
sleep 10

# Dismiss potential popups (Safe Mode, etc.)
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Focusing window $WID..."
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# 4. Capture Initial Evidence
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Initial Count: $INITIAL_COUNT"
echo "Max ID: $MAX_ID"