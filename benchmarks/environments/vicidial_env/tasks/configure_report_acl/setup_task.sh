#!/bin/bash
set -e

echo "=== Setting up Configure Report ACL task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Clean state: Remove the group if it already exists from a previous run
echo "Cleaning up previous task artifacts..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_user_groups WHERE user_group='SUP_SECURE';" \
    >/dev/null 2>&1 || true

# Record initial count of user groups (for "do nothing" detection)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_user_groups;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_group_count.txt

# Launch Firefox to the User Groups section to save time/clicks, 
# or just the admin menu. Let's start at Admin Menu to test navigation.
TARGET_URL="${VICIDIAL_ADMIN_URL}"

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$TARGET_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for window and focus
wait_for_window "firefox\|mozilla\|vicidial" 30
focus_firefox
maximize_active_window

# Handle potential login (if session expired or fresh start)
# We assume the standard login flow might be needed
sleep 2
if DISPLAY=:1 xdotool search --name "Vicidial Admin" > /dev/null 2>&1; then
    echo "Vicidial Admin login likely needed..."
    # Attempt blind login just in case we are at the prompt
    DISPLAY=:1 xdotool type --delay 50 "6666"
    DISPLAY=:1 xdotool key Tab
    DISPLAY=:1 xdotool type --delay 50 "andromeda"
    DISPLAY=:1 xdotool key Return
    sleep 3
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="