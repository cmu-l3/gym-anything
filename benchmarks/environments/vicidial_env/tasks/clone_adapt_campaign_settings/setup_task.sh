#!/bin/bash
set -e
echo "=== Setting up clone_adapt_campaign_settings task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL readiness
echo "Waiting for MySQL..."
for i in $(seq 1 60); do
  if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
    echo "MySQL is ready"
    break
  fi
  sleep 2
done

# 1. Create source campaign SENPOLL with specific "tuned" settings
# We use specific values that are unlikely to be entered by default/accident
echo "Creating source campaign SENPOLL..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
DELETE FROM vicidial_campaigns WHERE campaign_id='SENPOLL';
INSERT INTO vicidial_campaigns (
  campaign_id, campaign_name, active, dial_method, auto_dial_level,
  dial_timeout, drop_call_seconds, campaign_cid, manual_dial_prefix,
  voicemail_ext, local_call_time, campaign_script
) VALUES (
  'SENPOLL', 'Senate Polling East', 'Y', 'ADAPT_TAPERED', '1.25',
  '28', '5', '2025550100', '1',
  '85026666', '24hours', 'SENPOLLSC'
);"

# 2. Ensure target campaign SEN_WEST does NOT exist
echo "Cleaning up target campaign SEN_WEST..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_campaigns WHERE campaign_id='SEN_WEST';"

# 3. Setup Firefox
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true

# Authenticate via URL parameters to bypass Basic Auth prompt if needed, 
# though Vicidial usually uses form auth. We'll load the admin page.
# Using 6666/andromeda
LOGIN_URL="${VICIDIAL_ADMIN_URL}"

su - ga -c "DISPLAY=:1 firefox '${LOGIN_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "Firefox\|Mozilla\|Vicidial" 30
maximize_active_window
focus_firefox

# Perform Login if on login screen
sleep 5
echo "Attempting auto-login..."
DISPLAY=:1 xdotool type "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type "andromeda"
DISPLAY=:1 xdotool key Return
sleep 5

# Navigate to Campaigns screen explicitly to set the context
navigate_to_url "${VICIDIAL_ADMIN_URL}?ADD=10"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="