#!/bin/bash
echo "=== Setting up approve_pending_user task ==="

source /workspace/scripts/task_utils.sh

# Record initial approved user count
INITIAL_APPROVED=$(get_approved_user_count)
echo "$INITIAL_APPROVED" | sudo tee /tmp/initial_approved_count > /dev/null
sudo chmod 666 /tmp/initial_approved_count

# Record initial pending count
INITIAL_PENDING=$(get_pending_user_count)
echo "$INITIAL_PENDING" | sudo tee /tmp/initial_pending_count > /dev/null
sudo chmod 666 /tmp/initial_pending_count

# Verify Sarah Mitchell exists and is pending
SARAH_STATUS=$(opencad_db_query "SELECT approved FROM users WHERE email='sarah.mitchell@opencad.local'")
echo "Sarah Mitchell approval status: $SARAH_STATUS"

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
