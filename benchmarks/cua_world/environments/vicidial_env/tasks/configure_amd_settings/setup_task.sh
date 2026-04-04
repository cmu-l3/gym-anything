#!/bin/bash
set -e
echo "=== Setting up AMD Configuration Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Reset the target campaign 'AMD_OPTIM' to a clean state
# Defaults: Routing=8368 (No AMD), Silence=2500, Word=5000, Greet=1500
echo "Resetting AMD_OPTIM campaign state..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT INTO vicidial_campaigns (campaign_id, campaign_name, active, dial_method, auto_dial_level, campaign_vdad_exten, campaign_cid, campaign_rec, amd_send_to_vmx, amd_initial_silence, amd_maximum_word_length, amd_maximum_greeting) 
VALUES ('AMD_OPTIM', 'AMD Optimization Test', 'Y', 'RATIO', '1.0', '8368', '7275551234', 'NEVER', 'N', '2500', '5000', '1500')
ON DUPLICATE KEY UPDATE 
campaign_vdad_exten='8368', 
amd_send_to_vmx='N', 
amd_initial_silence='2500', 
amd_maximum_word_length='5000', 
amd_maximum_greeting='1500',
active='Y',
campaign_name='AMD Optimization Test';
" 2>/dev/null

# Record initial state for debugging
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT campaign_vdad_exten, amd_initial_silence FROM vicidial_campaigns WHERE campaign_id='AMD_OPTIM'" > /tmp/initial_db_state.txt

# Start Firefox and navigate to Campaigns list
# We start at the main campaign listing to require navigation
START_URL="${VICIDIAL_ADMIN_URL}?ADD=10"

if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '${START_URL}' > /dev/null 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30

# Maximize and focus
maximize_active_window
focus_firefox

# Navigate to URL explicitly to ensure we are on the right page
navigate_to_url "$START_URL"

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="