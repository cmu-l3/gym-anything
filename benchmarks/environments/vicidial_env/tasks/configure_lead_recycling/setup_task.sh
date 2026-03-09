#!/bin/bash
set -e

echo "=== Setting up Configure Lead Recycling Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL to be ready inside container
echo "Waiting for Vicidial MySQL..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# 1. Create the Campaign 'SALESCAMP' if not exists
# We use INSERT IGNORE to be idempotent
echo "Creating campaign SALESCAMP..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT IGNORE INTO vicidial_campaigns 
(campaign_id, campaign_name, active, dial_method, auto_dial_level, campaign_cid, local_call_time, dial_prefix) 
VALUES 
('SALESCAMP', 'Sales Outreach Campaign', 'Y', 'MANUAL', '0', '0000000000', 'default', '9');
"

# 2. Clean up any existing recycling rules for this campaign (Start Clean)
echo "Cleaning existing recycling rules..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_lead_recycle WHERE campaign_id = 'SALESCAMP';"

# 3. Record initial count (should be 0)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_lead_recycle WHERE campaign_id = 'SALESCAMP';" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_recycle_count.txt
echo "Initial recycling rules count: $INITIAL_COUNT"

# 4. Launch Firefox and login
echo "Launching Firefox..."
# Kill any existing firefox
pkill -f firefox 2>/dev/null || true

# Start Firefox pointing to admin
VICIDIAL_ADMIN_URL="http://localhost/vicidial/admin.php"
su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 60
focus_firefox
maximize_active_window

# Handle Login (Basic Auth or Form)
# In this environment, we might hit the HTTP Basic Auth prompt or the PHP form.
# The setup script creates a user '6666' / 'andromeda'.
# We will blindly type credentials just in case Basic Auth is active, then fall back to form interactions if needed by the agent.
# (Agent is expected to log in, but we can pre-fill or get past basic auth if it blocks interaction)

sleep 5
echo "Attempting to dismiss potential Basic Auth or Login..."
# If it's basic auth:
DISPLAY=:1 xdotool type "6666"
sleep 0.5
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type "andromeda"
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 5

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="