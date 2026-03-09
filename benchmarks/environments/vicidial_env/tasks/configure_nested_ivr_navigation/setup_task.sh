#!/bin/bash
set -e

echo "=== Setting up Configure Nested IVR Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Vicidial is running
vicidial_ensure_running

# 3. Clean up database state (Idempotency)
echo "Cleaning up previous task artifacts..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_inbound_groups WHERE group_id IN ('TC_SALES', 'TC_TECH');" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_call_menu WHERE menu_id IN ('MENU_MAIN', 'MENU_SUB_SUP');" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_call_menu_options WHERE menu_id IN ('MENU_MAIN', 'MENU_SUB_SUP');" 2>/dev/null || true

# 4. Prepare Browser
# Kill existing
pkill -f firefox 2>/dev/null || true

# Start Firefox on Admin Page
# Note: Admin URL usually requires Basic Auth. 
# We launch, wait, and type credentials if needed, or rely on URL embedding if supported.
START_URL="${VICIDIAL_ADMIN_URL}"
echo "Launching Firefox at $START_URL..."

su - ga -c "DISPLAY=:1 firefox --new-window '${START_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox|mozilla|vicidial" 60

# Maximize
focus_firefox
maximize_active_window

# Handle Basic Auth if it appears (common in Vicidial setups)
sleep 2
echo "Attempting login automation..."
DISPLAY=:1 xdotool type --delay 50 "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type --delay 50 "andromeda"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="