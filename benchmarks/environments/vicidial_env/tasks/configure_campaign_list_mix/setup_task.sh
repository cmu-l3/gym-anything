#!/bin/bash
set -e
echo "=== Setting up Configure Campaign List Mix Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL to be ready
echo "Waiting for Database..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Prepare Database State
echo "Preparing Database content..."

# 1. Clean up previous run artifacts
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
DELETE FROM vicidial_campaigns WHERE campaign_id='SENMIX';
DELETE FROM vicidial_lists WHERE list_id IN ('9301', '9302', '9303');
DELETE FROM vicidial_campaigns_list_mix WHERE vcl_id='REGIONAL_BLEND';
DELETE FROM vicidial_campaigns_list_mix_entry WHERE vcl_id='REGIONAL_BLEND';
"

# 2. Create Campaign SENMIX
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT INTO vicidial_campaigns (campaign_id, campaign_name, active, dial_method, auto_dial_level, lead_order) 
VALUES ('SENMIX', 'Senator Mix Survey', 'Y', 'RATIO', '1', 'DOWN');
"

# 3. Create Lists (9301, 9302, 9303)
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT INTO vicidial_lists (list_id, list_name, campaign_id, active) VALUES 
('9301', 'Northeast Senators', 'SENMIX', 'Y'),
('9302', 'Southern Senators', 'SENMIX', 'Y'),
('9303', 'Western Senators', 'SENMIX', 'Y');
"

# 4. Record initial state of list mix (should be 0)
INITIAL_MIX_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_campaigns_list_mix WHERE vcl_id='REGIONAL_BLEND'" 2>/dev/null || echo "0")
echo "$INITIAL_MIX_COUNT" > /tmp/initial_mix_count.txt

# Start Firefox and navigate to Admin Login
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true

# Pre-auth URL to bypass basic auth prompt if configured, or just land on admin page
START_URL="${VICIDIAL_ADMIN_URL}"

su - ga -c "DISPLAY=:1 firefox --new-window '${START_URL}' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox
wait_for_window "firefox|mozilla" 30
focus_firefox
maximize_active_window

# Initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="