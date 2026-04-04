#!/bin/bash
set -e
echo "=== Setting up configure_predictive_dialer task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL to be ready
echo "Waiting for Vicidial MySQL..."
for i in $(seq 1 60); do
  if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
    echo "MySQL is ready"
    break
  fi
  sleep 2
  if [ "$i" -eq 60 ]; then
    echo "FATAL: MySQL did not become ready"
    exit 1
  fi
done

# Clean up any existing campaign to ensure clean state
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "DELETE FROM vicidial_campaigns WHERE campaign_id='SALESOUT';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "DELETE FROM vicidial_campaign_stats WHERE campaign_id='SALESOUT';" 2>/dev/null || true

# Insert campaign with DEFAULT/INCORRECT values
# These are the values the agent must CHANGE
echo "Creating SALESOUT campaign with default values..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT INTO vicidial_campaigns (
  campaign_id, campaign_name, active, dial_method, auto_dial_level, 
  dial_timeout, hopper_level, campaign_rec, drop_call_seconds, campaign_cid,
  lead_order, dial_status_a, dial_status_b, dial_status_c, dial_status_d, dial_status_e
) VALUES (
  'SALESOUT', 'Sales Outbound Campaign', 'Y', 'MANUAL', '1.0', 
  '60', '10', 'NEVER', '10', '0000000000',
  'DOWN', 'NEW', '', '', '', ''
);"

# Create required stats record
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT IGNORE INTO vicidial_campaign_stats (campaign_id) VALUES ('SALESOUT');
"

# Record initial values for anti-gaming checks
# We query what we just inserted to be sure
echo "Recording initial state..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e \
  "SELECT dial_method, auto_dial_level, hopper_level, dial_timeout, campaign_rec, drop_call_seconds, campaign_cid \
   FROM vicidial_campaigns WHERE campaign_id='SALESOUT'" > /tmp/initial_values_raw.txt

# Convert to JSON for easier Python parsing later
dial_method=$(awk '{print $1}' /tmp/initial_values_raw.txt)
auto_dial=$(awk '{print $2}' /tmp/initial_values_raw.txt)
hopper=$(awk '{print $3}' /tmp/initial_values_raw.txt)
timeout=$(awk '{print $4}' /tmp/initial_values_raw.txt)
rec=$(awk '{print $5}' /tmp/initial_values_raw.txt)
drop=$(awk '{print $6}' /tmp/initial_values_raw.txt)
cid=$(awk '{print $7}' /tmp/initial_values_raw.txt)

cat > /tmp/initial_state.json << EOF
{
  "dial_method": "$dial_method",
  "auto_dial_level": "$auto_dial",
  "hopper_level": "$hopper",
  "dial_timeout": "$timeout",
  "campaign_rec": "$rec",
  "drop_call_seconds": "$drop",
  "campaign_cid": "$cid"
}
EOF

# Setup Firefox
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true

# Admin URL with auto-login params is not standard, so we assume standard auth or open session.
# Since the env setup handles auth or we rely on the agent to login if needed.
# However, for a fair task start, we should try to get them to the page.
# The env setup script sets up a session or we can pass creds. 
# We'll open the main admin page.
TARGET_URL="http://localhost/vicidial/admin.php?ADD=34&campaign_id=SALESOUT"

su - ga -c "DISPLAY=:1 firefox '$TARGET_URL' > /tmp/firefox.log 2>&1 &"

# Wait for window
wait_for_window "firefox|mozilla|vicidial" 30
focus_firefox
maximize_active_window

# Handle HTTP Basic Auth if it pops up (User: 6666, Pass: andromeda)
sleep 2
DISPLAY=:1 xdotool type --delay 50 "6666" 2>/dev/null || true
DISPLAY=:1 xdotool key Tab 2>/dev/null || true
DISPLAY=:1 xdotool type --delay 50 "andromeda" 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Wait a moment for page load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="