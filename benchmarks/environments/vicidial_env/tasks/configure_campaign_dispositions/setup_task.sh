#!/bin/bash
set -e

echo "=== Setting up Configure Campaign Dispositions Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial services are running
vicidial_ensure_running

echo "Initializing Database State..."

# 1. Ensure Campaign SURVEY01 exists
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "INSERT IGNORE INTO vicidial_campaigns (campaign_id, campaign_name, active, dial_method, auto_dial_level, campaign_cid) VALUES ('SURVEY01', 'Political Survey Campaign', 'Y', 'MANUAL', '0', '0000000000');" 2>/dev/null

# 2. CLEAR any existing statuses for this campaign to ensure clean start
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_campaign_statuses WHERE campaign_id='SURVEY01';" 2>/dev/null

# 3. Record initial count (should be 0)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT COUNT(*) FROM vicidial_campaign_statuses WHERE campaign_id='SURVEY01';" 2>/dev/null)
echo "$INITIAL_COUNT" > /tmp/initial_status_count.txt
echo "Initial status count for SURVEY01: $INITIAL_COUNT"

# 4. Ensure Admin User 6666 has permissions
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "UPDATE vicidial_users SET modify_campaigns='1', modify_statuses='1' WHERE user='6666';" 2>/dev/null

# Prepare Browser
echo "Launching Firefox..."
VICIDIAL_ADMIN_URL="http://localhost/vicidial/admin.php"

# Kill existing
pkill -f firefox 2>/dev/null || true

# Start Firefox
su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_ADMIN_URL' > /dev/null 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30

# Maximize
focus_firefox
maximize_active_window

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="