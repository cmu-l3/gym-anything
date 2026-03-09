#!/bin/bash
set -e
echo "=== Setting up configure_automated_broadcast_survey task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL to be fully ready
echo "Waiting for Vicidial MySQL..."
for i in $(seq 1 60); do
  if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# Reset EMRGNCY campaign to a clean state (Manual dial, Survey disabled)
echo "Resetting EMRGNCY campaign configuration..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
DELETE FROM vicidial_campaigns WHERE campaign_id='EMRGNCY';
INSERT INTO vicidial_campaigns (
    campaign_id, campaign_name, active, dial_method, auto_dial_level, 
    lead_order, dial_statuses, campaign_description, survey_first_audio_file,
    survey_dtmf_digits, survey_ni_digit, survey_ni_status, survey_wait_seconds,
    survey_method, survey_extension, survey_no_response_action
) VALUES (
    'EMRGNCY', 'City Emergency Alert', 'Y', 'MANUAL', '1', 
    'DOWN', 'NEW', 'Emergency Notification System', '',
    '', '', '', 10,
    'AGENT_XFER', '8300', 'OPTIN'
);"

# Record initial state for verification
# We record the initial values of the fields we expect to change
INITIAL_STATE=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "
SELECT survey_first_audio_file, survey_dtmf_digits, survey_ni_digit, survey_ni_status, 
       survey_wait_seconds, survey_method, survey_extension, survey_no_response_action 
FROM vicidial_campaigns WHERE campaign_id='EMRGNCY';
" 2>/dev/null || echo "")
echo "$INITIAL_STATE" > /tmp/initial_campaign_state.txt

# Launch Firefox if not running
if ! pgrep -f "firefox" > /dev/null; then
    echo "Launching Firefox..."
    su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /tmp/firefox_vicidial.log 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30

# Maximize and focus
maximize_active_window
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="