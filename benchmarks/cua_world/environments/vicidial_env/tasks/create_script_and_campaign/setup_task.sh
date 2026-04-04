#!/bin/bash
set -e

echo "=== Setting up Create Script and Campaign task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Clean up any previous state to ensure a clean start
echo "Cleaning up previous records..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_scripts WHERE script_id='SENATE_V1';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_campaigns WHERE campaign_id='SENATE_OPS';" 2>/dev/null || true

# Record initial counts (should be 0)
INIT_SCRIPT_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_scripts WHERE script_id='SENATE_V1';" 2>/dev/null || echo "0")
INIT_CAMPAIGN_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_campaigns WHERE campaign_id='SENATE_OPS';" 2>/dev/null || echo "0")

echo "$INIT_SCRIPT_COUNT" > /tmp/initial_script_count.txt
echo "$INIT_CAMPAIGN_COUNT" > /tmp/initial_campaign_count.txt

# Prepare Firefox
# Kill existing instances
pkill -f firefox 2>/dev/null || true

# Start Firefox on Admin login or Home
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for Firefox
wait_for_window "firefox\|mozilla\|vicidial" 60

# Focus and maximize
focus_firefox
maximize_active_window

# Handle Login if needed (6666/andromeda)
# Note: vicidial_env often has basic auth or form login. 
# We'll assume the user is logged in or the environment handles basic auth via URL in previous steps if configured.
# If not, we perform a basic login check.

sleep 3
# Check if we are on login screen and need to type credentials (if not auto-logged via URL)
# For this env, we rely on the user/agent to log in if presented with a screen, 
# or the env setup to have handled basic auth. 
# We will just ensure the window is ready.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="