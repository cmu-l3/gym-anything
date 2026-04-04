#!/bin/bash
set -e

echo "=== Setting up Configure Campaign Recording task ==="

source /workspace/scripts/task_utils.sh

# Ensure Vicidial is running
vicidial_ensure_running

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# DATABASE PREPARATION
# ==============================================================================
echo "Resetting campaign FINSVC01 to initial state..."

# We use docker exec to run MySQL commands inside the container.
# We insert the campaign if missing, or update it to 'NEVER' recording if present.
# This ensures the agent must actually do work.

SQL_SETUP="INSERT INTO vicidial_campaigns 
(campaign_id, campaign_name, active, dial_method, auto_dial_level, campaign_rec, campaign_rec_filename, allcalls_delay, dial_prefix, manual_dial_prefix, campaign_cid, lead_order, park_ext, park_file_name, allow_closers, hopper_level, dial_timeout, agent_alert_delay, reset_hopper, dial_statuses, list_order_mix) 
VALUES 
('FINSVC01', 'Financial Services Outbound', 'Y', 'MANUAL', '0', 'NEVER', '', '0', '9', '9', '0000000000', 'DOWN', '8600', 'default', 'Y', '100', '60', '1000', 'Y', ' NEW -', 'DISABLED') 
ON DUPLICATE KEY UPDATE 
campaign_rec='NEVER', campaign_rec_filename='', allcalls_delay='0';"

docker exec vicidial mysql -ucron -p1234 -D asterisk -e "$SQL_SETUP"

# Verify initial state and record it
INITIAL_STATE=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sNe "SELECT campaign_rec, campaign_rec_filename, allcalls_delay FROM vicidial_campaigns WHERE campaign_id='FINSVC01'")
echo "$INITIAL_STATE" > /tmp/initial_db_state.txt
echo "Initial DB State (Rec, Filename, Delay): $INITIAL_STATE"

# ==============================================================================
# BROWSER SETUP
# ==============================================================================
echo "Launching Firefox..."

# Vicidial Admin URL
ADMIN_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"

# Kill existing instances
pkill -f firefox 2>/dev/null || true

# Start Firefox
su - ga -c "DISPLAY=:1 firefox '$ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30

# Focus and maximize
focus_firefox
maximize_active_window

# Handle HTTP Basic Auth if it appears (common in Vicidial setups)
# We blindly type credentials just in case the dialog is focused
sleep 2
DISPLAY=:1 xdotool type "6666" 2>/dev/null || true
DISPLAY=:1 xdotool key Tab 2>/dev/null || true
DISPLAY=:1 xdotool type "andromeda" 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Capture initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="