#!/bin/bash
set -e

echo "=== Setting up task: create_user_group_permissions ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running and web UI is reachable
vicidial_ensure_running

# Remove any pre-existing PRMSALES group (clean state)
echo "Cleaning up any pre-existing PRMSALES user group..."
if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1" >/dev/null 2>&1; then
    docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
      "DELETE FROM vicidial_user_groups WHERE user_group = 'PRMSALES';" \
      >/dev/null 2>&1 || true
fi

# Record initial count of user groups for comparison
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_user_groups;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_group_count.txt
echo "Initial user group count: $INITIAL_COUNT"

# Kill any existing Firefox instances and restart cleanly
pkill -f firefox 2>/dev/null || true
sleep 2

ADMIN_URL="http://localhost/vicidial/admin.php"

# Launch Firefox to Vicidial admin
# Note: Vicidial uses HTTP Basic Auth. We navigate to the URL. 
# The agent or automated login below handles auth.
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '${ADMIN_URL}' > /tmp/firefox_vicidial.log 2>&1 &"
sleep 5

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|vicidial" 30

# Attempt to handle Basic Auth if it appears (Vicidial often prompts this)
# Typing credentials blindly into the active window
echo "Attempting to handle Basic Auth prompt..."
sleep 2
DISPLAY=:1 xdotool type --delay 50 "6666"
sleep 0.5
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type --delay 50 "andromeda"
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 5

# Focus and maximize
maximize_active_window
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="