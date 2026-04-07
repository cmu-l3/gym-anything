#!/bin/bash
echo "=== Setting up manage_trespassing_incident task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous runs to ensure no ambiguity
# We delete any calls (active or history) involving 'Foreman Mike' at 'Quarry Main Gate'
echo "Cleaning up potential collision data..."
opencad_db_query "DELETE FROM calls WHERE caller LIKE '%Foreman Mike%' OR call_location LIKE '%Quarry Main Gate%'"
opencad_db_query "DELETE FROM call_history WHERE caller LIKE '%Foreman Mike%' OR call_location LIKE '%Quarry Main Gate%'"

# 2. Record initial counts (just in case)
INITIAL_CALLS=$(get_call_count)
echo "$INITIAL_CALLS" > /tmp/initial_call_count

# 3. Prepare Firefox
# Remove profile locks to prevent startup errors
rm -f /home/ga/.mozilla/firefox/default-release/lock /home/ga/.mozilla/firefox/default-release/.parentlock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to the Login Page
echo "Launching Firefox..."
DISPLAY=:1 firefox "http://localhost/index.php" &
sleep 10

# Dismiss any "Make Firefox Default" bars or popups
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize the browser window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="