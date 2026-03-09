#!/bin/bash
set -e

echo "=== Setting up Configure Xfer Presets task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Vicidial is running
vicidial_ensure_running

# 2. Prepare Database State (Clean Slate)
echo "Configuring database for SALESTEAM campaign..."

# Create Campaign if not exists
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "INSERT IGNORE INTO vicidial_campaigns (campaign_id, campaign_name, active, dial_method, auto_dial_level, local_call_time) VALUES ('SALESTEAM', 'Sales Team Outbound', 'Y', 'MANUAL', '0', 'default');" 2>/dev/null

# Clear any existing presets for this campaign to ensure task requires action
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "DELETE FROM vicidial_xfer_presets WHERE campaign_id='SALESTEAM';" 2>/dev/null

# Record initial count (should be 0)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_xfer_presets WHERE campaign_id='SALESTEAM';" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_preset_count.txt

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Launch Firefox to the specific Campaign Modification page
# This saves the agent from getting lost in the main menu initially, though they still have to find the Presets section.
CAMPAIGN_URL="${VICIDIAL_ADMIN_URL}?ADD=31&campaign_id=SALESTEAM"

# Kill existing firefox instances
pkill -f firefox 2>/dev/null || true

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '${CAMPAIGN_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 60

# Focus and maximize
focus_firefox
maximize_active_window

# Handle HTTP Basic Auth (Vicidial default credentials)
# We type them blindly into the focused window which should be the auth prompt or the page
echo "Handling potential authentication..."
sleep 2
DISPLAY=:1 xdotool type --delay 50 "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type --delay 50 "andromeda"
DISPLAY=:1 xdotool key Return

sleep 5

# Verify we are loaded (check for window title)
if DISPLAY=:1 wmctrl -l | grep -i "Sales Team Outbound"; then
    echo "Campaign page loaded successfully."
else
    # Retry navigation if auth redirected elsewhere
    navigate_to_url "$CAMPAIGN_URL"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="