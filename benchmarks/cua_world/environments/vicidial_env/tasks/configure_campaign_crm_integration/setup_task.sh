#!/bin/bash
set -e

echo "=== Setting up Configure Campaign CRM Integration task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL to be ready
echo "Waiting for database..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Prepare the database state:
# 1. Ensure SALESTEAM campaign exists
# 2. Reset the integration fields to empty/default to ensure the agent actually does the work
echo "Preparing campaign data..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT IGNORE INTO vicidial_campaigns (campaign_id, campaign_name, active, dial_method, auto_dial_level) 
VALUES ('SALESTEAM', 'Sales Team Outbound', 'Y', 'MANUAL', '0');
"

docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
UPDATE vicidial_campaigns 
SET web_form_address='', 
    web_form_target='_top', 
    dispo_call_url='' 
WHERE campaign_id='SALESTEAM';
"

# Record initial state for debugging/verification
docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "
SELECT web_form_address, web_form_target, dispo_call_url FROM vicidial_campaigns WHERE campaign_id='SALESTEAM';
" > /tmp/initial_db_state.txt

# Start Firefox and navigate to the Campaign main screen
# We land them on the Campaign List to save a few clicks, but they still need to find the specific campaign
echo "Launching Firefox..."
TARGET_URL="${VICIDIAL_ADMIN_URL}?ADD=10" # ADD=10 is usually the Campaigns List view

# Check if Firefox is already running
if ! pgrep -f "firefox" > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$TARGET_URL' > /dev/null 2>&1 &"
else
    # Navigate existing instance
    navigate_to_url "$TARGET_URL"
fi

wait_for_window "Firefox\|Mozilla" 30
focus_firefox
maximize_active_window

# Handle Login if redirected
sleep 3
# Simple check if we are on login screen (by title or URL, simpler to just type creds blindly if needed or rely on session)
# In this env, we might need to re-auth. Let's assume standard auth flow or session persistence.
# For robustness, we'll type credentials if we suspect we are at login, but usually env Setup handles this.
# We'll just ensure window is focused.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="