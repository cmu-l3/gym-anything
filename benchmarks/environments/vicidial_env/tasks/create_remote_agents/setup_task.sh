#!/bin/bash
set -e
echo "=== Setting up create_remote_agents task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
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

# Clean up any existing remote agents for these users to ensure clean state
echo "Cleaning up old remote agents..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
DELETE FROM vicidial_remote_agents WHERE user_start IN ('7201','7202','7203');
" 2>/dev/null || true

# Record initial count (should be 0 for these specific users, but count total for anti-gaming)
INITIAL_TOTAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sN -e \
  "SELECT COUNT(*) FROM vicidial_remote_agents;" 2>/dev/null || echo "0")
echo "$INITIAL_TOTAL_COUNT" > /tmp/initial_ra_count.txt

# Create the WFHCAMP campaign if it doesn't exist
echo "Creating campaign WFHCAMP..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT IGNORE INTO vicidial_campaigns (
  campaign_id, campaign_name, active, dial_method, auto_dial_level, 
  dial_status_a, dial_status_b, dial_status_c, dial_status_d, dial_status_e,
  lead_order, park_ext, park_file_name, web_form_address,
  allow_closers, hopper_level, adaptive_dropped_percentage,
  campaign_changedate, campaign_stats_refresh, local_call_time
) VALUES (
  'WFHCAMP', 'Work From Home Campaign', 'Y', 'RATIO', 1.0,
  'NEW', '', '', '', '',
  'DOWN', '8301', 'park.gsm', '',
  'Y', 100, 3.0,
  NOW(), 'Y', 'default'
) ON DUPLICATE KEY UPDATE campaign_name='Work From Home Campaign';
" 2>/dev/null || echo "WARNING: Could not create campaign WFHCAMP"

# Create 3 agent user accounts (7201, 7202, 7203)
echo "Creating user accounts..."
for uid in 7201 7202 7203; do
  docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
  INSERT IGNORE INTO vicidial_users (
    user, pass, full_name, user_level, user_group, active
  ) VALUES (
    '${uid}', 'test1234', 'Remote Agent ${uid}', 1, 'ADMIN', 'Y'
  );" 2>/dev/null || echo "WARNING: Could not create user $uid"
done

# Launch Firefox and navigate to Remote Agents section
# We authenticate first via URL parameters if possible, or just land on admin page
# Note: The environment usually handles basic auth via standard user, but we'll load the page.
VICIDIAL_ADMIN_URL="http://localhost/vicidial/admin.php?ADD=140000000000" # Link to Remote Agents listing

pkill -f firefox 2>/dev/null || true
sleep 1

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_ADMIN_URL' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for window
wait_for_window "firefox|mozilla|vicidial" 30 || true

# Maximize
maximize_active_window

# Handle Basic Auth if needed (environment specific, but good practice)
sleep 2
DISPLAY=:1 xdotool type "6666" 2>/dev/null || true
DISPLAY=:1 xdotool key Tab 2>/dev/null || true
DISPLAY=:1 xdotool type "andromeda" 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true

sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="