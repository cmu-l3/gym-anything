#!/bin/bash
set -e
echo "=== Setting up Tune Campaign Dialing task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Vicidial is running
vicidial_ensure_running

# 2. Wait for MySQL to be ready
echo "Waiting for MySQL..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# 3. Reset/Prepare the NURTURE campaign state
# We want a specific bad state: Only NEW status, No filter, Default timeout/drop
echo "Resetting NURTURE campaign state..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
    DELETE FROM vicidial_campaigns WHERE campaign_id='NURTURE';
    INSERT INTO vicidial_campaigns (campaign_id, campaign_name, active, dial_method, auto_dial_level, dial_timeout, adaptive_dropped_percentage, lead_filter_id, dial_statuses)
    VALUES ('NURTURE', 'Nurture Leads', 'Y', 'RATIO', '1.0', 60, 3, 'NONE', ' NEW ');
"

# 4. Ensure the target filter does NOT exist (force agent to create it)
echo "Removing target lead filter..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
    DELETE FROM vicidial_lead_filters WHERE lead_filter_id='MAX_5_TRIES';
"

# 5. Launch Firefox to Admin Panel
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true

# Login URL with auto-login parameters (standard Vicidial behavior)
ADMIN_URL="http://localhost/vicidial/admin.php?ADD=100000000000"

su - ga -c "DISPLAY=:1 firefox '$ADMIN_URL' > /dev/null 2>&1 &"

# 6. Window Management
wait_for_window "firefox\|vicidial" 60
focus_firefox
maximize_active_window

# 7. Authenticate (Basic Auth)
# Wait for browser to actually load and show the prompt
sleep 5
echo "Entering credentials..."
DISPLAY=:1 xdotool type --delay 20 "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type --delay 20 "andromeda"
DISPLAY=:1 xdotool key Return

sleep 5

# 8. Record setup evidence
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="