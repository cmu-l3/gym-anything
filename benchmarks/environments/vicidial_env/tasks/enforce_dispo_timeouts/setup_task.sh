#!/bin/bash
set -e

echo "=== Setting up Enforce Dispo Timeouts Task ==="

source /workspace/scripts/task_utils.sh

# Ensure Vicidial services are up
vicidial_ensure_running

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# CLEAN STATE: Remove the target campaign and status if they already exist
# This ensures the agent must actually create them
# ==============================================================================
echo "Cleaning up any existing configuration for FASTTRACK/DISPTO..."

# Delete campaign statuses for FASTTRACK
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_campaign_statuses WHERE campaign_id='FASTTRACK';" >/dev/null 2>&1 || true

# Delete campaign FASTTRACK
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_campaigns WHERE campaign_id='FASTTRACK';" >/dev/null 2>&1 || true

# Record initial count (should be 0)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT count(*) FROM vicidial_campaigns WHERE campaign_id='FASTTRACK'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_campaign_count.txt

# ==============================================================================
# BROWSER SETUP
# ==============================================================================
echo "Launching Firefox to Vicidial Admin..."

VICIDIAL_ADMIN_URL="http://localhost/vicidial/admin.php"

# Kill existing firefox instances
pkill -f firefox 2>/dev/null || true

# Start Firefox
su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /tmp/firefox_setup.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30

# Maximize and focus
focus_firefox
maximize_active_window

# Handle Login if needed (though env setup usually handles credentials, we ensure we are at login or logged in)
# The env setup puts credentials in valid user. Here we assume session might need refresh or fresh login.
# For simplicity in this task, we land on admin.php. If basic auth is handled by URL/browser profile, good.
# If form login is needed:
sleep 5
if DISPLAY=:1 xdotool search --name "Vicidial Admin" > /dev/null 2>&1; then
    echo "Already on Admin page"
else
    # Attempt login just in case
    echo "Attempting login..."
    DISPLAY=:1 xdotool type "6666"
    DISPLAY=:1 xdotool key Tab
    DISPLAY=:1 xdotool type "andromeda"
    DISPLAY=:1 xdotool key Return
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="