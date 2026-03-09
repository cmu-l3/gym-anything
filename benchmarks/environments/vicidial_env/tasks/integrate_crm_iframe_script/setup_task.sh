#!/bin/bash
set -e
echo "=== Setting up integrate_crm_iframe_script task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL readiness
for i in $(seq 1 60); do
  if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
    echo "MySQL is ready"
    break
  fi
  sleep 2
done

# Clean slate: Remove script if it exists and reset campaign
echo "Cleaning up previous state..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_scripts WHERE script_id='ORDERFLOW';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_campaigns WHERE campaign_id='SALES_Q1';" 2>/dev/null || true

# Create the target campaign 'SALES_Q1' (unconfigured)
echo "Creating initial SALES_Q1 campaign..."
# Note: dial_method=MANUAL is standard for initial setup to avoid unintended dialing
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT INTO vicidial_campaigns (campaign_id, campaign_name, active, dial_method, auto_dial_level, campaign_script, get_call_launch) 
VALUES ('SALES_Q1', 'Q1 Sales Outreach', 'Y', 'MANUAL', '0', '', 'NONE');
"

# Record initial count of scripts (anti-gaming)
INITIAL_SCRIPT_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_scripts WHERE script_id='ORDERFLOW';" 2>/dev/null || echo "0")
echo "$INITIAL_SCRIPT_COUNT" > /tmp/initial_script_count.txt

# Launch Firefox to Admin Panel
pkill -f firefox 2>/dev/null || true
# Navigate to Campaigns screen to start, as that's a logical place, or just main admin
START_URL="${VICIDIAL_ADMIN_URL}"

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '${START_URL}' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for Firefox window
wait_for_window "Firefox"
maximize_active_window

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="