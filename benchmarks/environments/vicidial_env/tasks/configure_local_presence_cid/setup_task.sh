#!/bin/bash
set -e

echo "=== Setting up Configure AC-CID Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial services are running
vicidial_ensure_running

echo "Preparing database state..."
# Wait for MySQL to be ready
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# 1. Ensure Campaign NEASTPRS exists (resetting if necessary)
# We recreate it or ensure it exists with default settings (AC-CID disabled initially)
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT IGNORE INTO vicidial_campaigns (campaign_id, campaign_name, active, dial_method, auto_dial_level, campaign_cid, areacode_cid) 
VALUES ('NEASTPRS', 'Northeast Presence', 'Y', 'MANUAL', '0', '2125559901', 'N');
UPDATE vicidial_campaigns SET areacode_cid='N' WHERE campaign_id='NEASTPRS';
"

# 2. Clear any existing AC-CID entries for this campaign to ensure clean start
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
DELETE FROM vicidial_campaign_cid_areacodes WHERE campaign_id='NEASTPRS';
"

# 3. Record initial count (should be 0)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_campaign_cid_areacodes WHERE campaign_id='NEASTPRS';" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_accid_count.txt
echo "Initial AC-CID count: $INITIAL_COUNT"

# 4. Launch Firefox and Login
# Kill any existing Firefox
pkill -f firefox 2>/dev/null || true

# Start Firefox at Admin Login
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 60

# Maximize
maximize_active_window

# Perform Login
echo "Logging in..."
sleep 2
DISPLAY=:1 xdotool type --delay 50 "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type --delay 50 "andromeda"
DISPLAY=:1 xdotool key Return

# Wait for login to complete (check for 'Campaigns' link or similar text in title/page)
sleep 5

# Navigate to Campaigns screen to save the agent one click (optional, but helpful context)
# We'll just leave them at the main menu or navigate to campaigns list
navigate_to_url "${VICIDIAL_ADMIN_URL}?ADD=10"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="