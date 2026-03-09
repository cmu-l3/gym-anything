#!/bin/bash
set -e

echo "=== Setting up Configure Campaign Blended Inbound task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Vicidial is running
vicidial_ensure_running

# 2. Prepare Database State (Reset/Create Campaign and Inbound Group)
echo "Preparing Vicidial database state..."

# Wait for MySQL
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Define IDs
CAMP_ID="SENATE"
INGROUP_ID="SENATE_CB"

# SQL Commands to reset state
# - Delete existing linkage
# - Ensure Campaign exists and is set to OUTBOUND ONLY (allow_closers='N')
# - Ensure Inbound Group exists
docker exec vicidial mysql -ucron -p1234 -D asterisk <<EOF
-- Cleanup linkage
DELETE FROM vicidial_campaign_ingroups WHERE campaign_id='$CAMP_ID' AND group_id='$INGROUP_ID';

-- Reset/Create Campaign SENATE
DELETE FROM vicidial_campaigns WHERE campaign_id='$CAMP_ID';
INSERT INTO vicidial_campaigns (campaign_id, campaign_name, active, allow_closers, dial_method, auto_dial_level, lead_order, dial_statuses, force_ftra_call_id)
VALUES ('$CAMP_ID', 'Senate Outreach Team', 'Y', 'N', 'MANUAL', '0', 'DOWN', ' NEW', '1');

-- Reset/Create Inbound Group SENATE_CB
DELETE FROM vicidial_inbound_groups WHERE group_id='$INGROUP_ID';
INSERT INTO vicidial_inbound_groups (group_id, group_name, active, queue_priority, next_agent_call, fronter_display, ingroup_recording_override)
VALUES ('$INGROUP_ID', 'Senate Callback Line', 'Y', '0', 'longest_wait_time', 'Y', 'DISABLED');

-- Ensure Admin user 6666 has permissions to modify campaigns
UPDATE vicidial_users SET modify_campaigns='1', modify_ingroups='1' WHERE user='6666';
EOF

echo "Database preparation complete."

# 3. Launch Firefox and login
# We start at the main admin screen to require navigation
START_URL="${VICIDIAL_ADMIN_URL}"

# Kill any existing firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
su - ga -c "DISPLAY=:1 firefox '$START_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 60

# Maximize
maximize_active_window

# Handle Basic Auth if needed (Standard Vicidial Docker behavior)
sleep 2
DISPLAY=:1 xdotool type "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type "andromeda"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="