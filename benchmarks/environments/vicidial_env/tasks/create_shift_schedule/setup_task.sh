#!/bin/bash
set -e

echo "=== Setting up create_shift_schedule task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial container is running
vicidial_ensure_running

# Wait for MySQL to be responsive
echo "Waiting for MySQL..."
for i in $(seq 1 60); do
  if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
    echo "MySQL is ready"
    break
  fi
  sleep 2
done

# CLEAN SLATE: Delete the target shift if it already exists
# This ensures the agent must actually create it
echo "Clearing any existing shift with ID WKDAY9TO5..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "DELETE FROM vicidial_shifts WHERE shift_id='WKDAY9TO5';" 2>/dev/null || true

# Record initial count of shifts (for anti-gaming verification)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_shifts;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_shift_count.txt
echo "Initial shift count: $INITIAL_COUNT"

# Prepare Browser
# Kill existing firefox instances to ensure clean start
pkill -f firefox 2>/dev/null || true
sleep 1

# Launch Firefox to the Admin panel
# We use the raw URL; the agent will likely encounter the Basic Auth dialog
ADMIN_URL="http://localhost/vicidial/admin.php"
echo "Launching Firefox at $ADMIN_URL..."

su - ga -c "DISPLAY=:1 firefox '$ADMIN_URL' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for Firefox window
wait_for_window "firefox|mozilla|vicidial" 30 || true

# Maximize and focus
focus_firefox
maximize_active_window
sleep 2

# Handle HTTP Basic Auth automatically to put agent at the starting line
# (This simulates the user already being logged into the browser session, 
# letting them focus on the Vicidial-specific task)
echo "Handling HTTP Basic Auth..."
DISPLAY=:1 xdotool type --delay 50 "6666"
sleep 0.5
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type --delay 50 "andromeda"
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 5

# Navigate explicitly to the Admin screen to be safe
navigate_to_url "$ADMIN_URL"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="