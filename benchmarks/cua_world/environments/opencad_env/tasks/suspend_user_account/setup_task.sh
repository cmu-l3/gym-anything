#!/bin/bash
echo "=== Setting up suspend_user_account task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure James Rodriguez is ACTIVE (approved=1) so he can be suspended
echo "Setting James Rodriguez to active state..."
opencad_db_query "UPDATE users SET approved=1, suspend_reason=NULL WHERE email='james.rodriguez@opencad.local'"

# 2. Ensure Admin is ACTIVE
opencad_db_query "UPDATE users SET approved=1 WHERE email='admin@opencad.local'"

# 3. Record initial state
INITIAL_STATUS=$(opencad_db_query "SELECT approved FROM users WHERE email='james.rodriguez@opencad.local'")
echo "$INITIAL_STATUS" > /tmp/initial_james_status.txt
echo "Initial James Status: $INITIAL_STATUS"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Prepare Browser
# Remove Firefox profile locks to prevent startup errors
rm -f /home/ga/.mozilla/firefox/default-release/lock /home/ga/.mozilla/firefox/default-release/.parentlock 2>/dev/null || true
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock /home/ga/snap/firefox/common/.mozilla/firefox/*/.parentlock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Start Firefox at Login page
DISPLAY=:1 firefox "http://localhost/index.php" &
sleep 10

# Dismiss Firefox popups/restore session dialogs
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial evidence screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="