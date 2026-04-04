#!/bin/bash
set -e
echo "=== Setting up configure_pause_codes task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure Vicidial services are running
vicidial_ensure_running

# 3. Wait for MySQL to be fully ready
echo "Waiting for Vicidial MySQL..."
for i in $(seq 1 60); do
  if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
    echo "MySQL is ready"
    break
  fi
  sleep 2
done

# 4. Prepare the specific campaign 'SALESQ1'
# If it doesn't exist, create it. If it does, ensure it's clean.
echo "Configuring campaign SALESQ1..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT IGNORE INTO vicidial_campaigns (
  campaign_id, campaign_name, active, dial_method, auto_dial_level,
  campaign_cid, local_call_time, lead_order, park_ext, park_file_name,
  web_form_address, allow_closers, hopper_level, dial_timeout,
  dial_prefix, campaign_changedate, campaign_stats_refresh
) VALUES (
  'SALESQ1', 'Sales Q1 2025', 'Y', 'RATIO', '1.0',
  '2125551234', '9am-9pm', 'DOWN', '8600', 'park',
  '', 'Y', '100', '60',
  '9', NOW(), 'Y'
);" 2>/dev/null || true

# 5. Clean state: Remove any existing pause codes for this campaign
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "DELETE FROM vicidial_pause_codes WHERE campaign_id='SALESQ1';" 2>/dev/null || true

# 6. Record initial count (should be 0)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_pause_codes WHERE campaign_id='SALESQ1';" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_pause_code_count.txt
echo "Initial pause code count for SALESQ1: $INITIAL_COUNT"

# 7. Ensure admin user 6666 has permissions
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "UPDATE vicidial_users SET modify_campaigns='1', modify_lists='1' WHERE user='6666';" \
  2>/dev/null || true

# 8. Launch Firefox to Admin login
pkill -f firefox 2>/dev/null || true
VICIDIAL_ADMIN_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30
maximize_active_window

# 9. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="