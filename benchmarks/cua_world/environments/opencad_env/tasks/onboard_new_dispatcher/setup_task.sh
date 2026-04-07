#!/bin/bash
echo "=== Setting up onboard_new_dispatcher task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up target user if exists (from previous runs)
echo "Cleaning up previous instances of 'Elena Ross'..."
opencad_db_query "DELETE FROM users WHERE email='elena.ross@opencad.local';"
opencad_db_query "DELETE FROM user_departments WHERE user_id IN (SELECT id FROM users WHERE email='elena.ross@opencad.local');"
opencad_db_query "DELETE FROM user_departments_temp WHERE user_id IN (SELECT id FROM users WHERE email='elena.ross@opencad.local');"

# 2. Record initial state
INITIAL_USER_COUNT=$(get_user_count)
echo "$INITIAL_USER_COUNT" | sudo tee /tmp/initial_user_count > /dev/null
sudo chmod 666 /tmp/initial_user_count

# Record max user ID to identify the new record later
MAX_USER_ID=$(opencad_db_query "SELECT COALESCE(MAX(id), 0) FROM users")
echo "${MAX_USER_ID:-0}" | sudo tee /tmp/baseline_max_user_id > /dev/null
sudo chmod 666 /tmp/baseline_max_user_id

# 3. Prepare Firefox
# Kill existing instances
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to the login page (or register page if direct link exists, usually index.php)
# Using index.php as the entry point
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

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="