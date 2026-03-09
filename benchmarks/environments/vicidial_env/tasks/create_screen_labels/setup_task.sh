#!/bin/bash
set -e
echo "=== Setting up Screen Labels task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Clean state: remove any existing HEALTH01 screen label to ensure a fresh start
echo "Cleaning any pre-existing HEALTH01 screen label..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "DELETE FROM vicidial_screen_labels WHERE label_id='HEALTH01';" 2>/dev/null || true

# Record initial state (should be 0)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_screen_labels WHERE label_id='HEALTH01';" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_label_count.txt
echo "Initial HEALTH01 count: $INITIAL_COUNT"

# Prepare Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to Admin Login
VICIDIAL_ADMIN_URL="http://localhost/vicidial/admin.php"
echo "Launching Firefox at $VICIDIAL_ADMIN_URL..."
su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30

# Maximize and focus
focus_firefox
maximize_active_window

# Handle Login
echo "Logging in..."
sleep 2
DISPLAY=:1 xdotool type --delay 50 "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type --delay 50 "andromeda"
DISPLAY=:1 xdotool key Return
sleep 5

# Verify we are logged in (check for "Admin" text in page title or content roughly)
# We'll just take a screenshot to confirm
take_screenshot /tmp/task_initial.png

echo "=== Screen Labels task setup complete ==="