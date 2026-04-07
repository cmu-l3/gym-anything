#!/bin/bash
echo "=== Setting up reset_user_password task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial password hash for James Rodriguez to detect changes
# We use docker exec to query the DB directly
INITIAL_HASH=$(opencad_db_query "SELECT password FROM users WHERE email='james.rodriguez@opencad.local'")
echo "$INITIAL_HASH" > /tmp/initial_hash.txt

# Ensure Firefox is clean and ready
echo "Preparing Firefox..."
# Kill existing instances
pkill -9 -f firefox 2>/dev/null || true
rm -f /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
rm -f /home/ga/.mozilla/firefox/default-release/.parentlock 2>/dev/null || true
sleep 2

# Start Firefox at login page
su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php' > /dev/null 2>&1 &"
sleep 10

# Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Dismiss Firefox popups/restoration prompts
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="