#!/bin/bash
set -e

echo "=== Setting up Create Inbound Group Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Vicidial is running
vicidial_ensure_running

# 2. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Clean state: Ensure the target inbound group does NOT exist
echo "Ensuring clean state (removing RECALL01 if exists)..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_inbound_groups WHERE group_id='RECALL01';" 2>/dev/null || true

# 4. Record initial count of inbound groups (for debugging)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_inbound_groups;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_group_count.txt

# 5. Launch Firefox to Vicidial Admin
# We use the Inbound section as a generic starting point, or just the main admin menu
START_URL="${VICIDIAL_ADMIN_URL}?ADD=300000000000" # Points to "Inbound" menu container

# Ensure no stale firefox instances
pkill -f firefox 2>/dev/null || true

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '$START_URL' > /tmp/firefox_task.log 2>&1 &"

# 6. Wait for window and maximize
wait_for_window "firefox|mozilla|vicidial" 60
focus_firefox
maximize_active_window

# 7. Handle Login (HTTP Basic Auth)
# The environment often prompts for Basic Auth. We type it in blindly to ensure access.
echo "Performing automated login..."
sleep 2
DISPLAY=:1 xdotool type --delay 50 "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type --delay 50 "andromeda"
DISPLAY=:1 xdotool key Return
sleep 5

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="