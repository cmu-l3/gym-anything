#!/bin/bash
set -e

echo "=== Setting up Configure Inbound Failover Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# ------------------------------------------------------------------
# DATABASE PREPARATION
# ------------------------------------------------------------------
echo "Preparing database state..."

# 1. Create/Reset Inbound Group 'SUPPORT' with default values
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
DELETE FROM vicidial_inbound_groups WHERE group_id='SUPPORT';
INSERT INTO vicidial_inbound_groups (group_id, group_name, active, group_color, call_time_id, after_hours_action, no_agent_no_queue_action, wait_hold_option, next_agent_call, web_form_address, web_form_address_two, get_call_launch)
VALUES ('SUPPORT', 'General Support Line', 'Y', 'blue', '24HOURS', 'MESSAGE', 'NONE', 'NONE', 'longest_wait_time', '', '', 'NONE');
"

# 2. Create Call Time 'BIZ_HRS' if not exists
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
DELETE FROM vicidial_call_times WHERE call_time_id='BIZ_HRS';
INSERT INTO vicidial_call_times (call_time_id, call_time_name, call_time_comments, ct_default_start, ct_default_stop)
VALUES ('BIZ_HRS', 'Business Hours 9-5', 'Mon-Fri 9am to 5pm', '0900', '1700');
"

# 3. Create Voicemail Box '8500' if not exists
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
DELETE FROM phones WHERE extension='8500';
DELETE FROM vicidial_voicemail WHERE voicemail_id='8500';
INSERT INTO vicidial_voicemail (voicemail_id, pass, fullname, active, email)
VALUES ('8500', '1234', 'General Support VM', 'Y', 'support@example.com');
"

# 4. Ensure Admin User '6666' has permissions to modify In-Groups
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
UPDATE vicidial_users SET modify_ingroups='1', user_level='9' WHERE user='6666';
"

echo "Database preparation complete."

# ------------------------------------------------------------------
# BROWSER SETUP
# ------------------------------------------------------------------
echo "Launching Firefox..."

# Log in loop to handle Basic Auth and Form Auth
# URL for Inbound Groups menu
TARGET_URL="${VICIDIAL_ADMIN_URL}?ADD=3000"

# Kill existing
pkill -f firefox 2>/dev/null || true

# Start Firefox
su - ga -c "DISPLAY=:1 firefox '$TARGET_URL' > /tmp/firefox.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 60

# Focus and Maximize
focus_firefox
maximize_active_window

# Handle Login
echo "Performing login..."
sleep 2
# Basic Auth (if prompted) or Form Login
# Vicidial often uses Basic Auth for the directory, then Form for the app, 
# or just Form depending on config. The environment script suggests Basic Auth might be present or Form.
# We'll try typing credentials blindly which works for both Basic Auth modal and HTML form if focused.
DISPLAY=:1 xdotool type "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type "andromeda"
DISPLAY=:1 xdotool key Return

sleep 5

# Ensure we are on the Inbound Groups page
# If login redirected elsewhere, navigate explicitly
navigate_to_url "$TARGET_URL"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="