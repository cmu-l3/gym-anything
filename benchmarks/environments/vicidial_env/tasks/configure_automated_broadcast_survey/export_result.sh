#!/bin/bash
set -e
echo "=== Exporting configure_automated_broadcast_survey result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Campaign Configuration
echo "Querying campaign configuration..."
CAMPAIGN_CONFIG=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "
SELECT 
    survey_first_audio_file, 
    survey_dtmf_digits, 
    survey_ni_digit, 
    survey_ni_status, 
    survey_wait_seconds, 
    survey_method, 
    survey_extension, 
    survey_no_response_action 
FROM vicidial_campaigns 
WHERE campaign_id='EMRGNCY';
" 2>/dev/null)

# Parse the tab-separated output into variables
# Using awk to handle potential empty fields gracefully
AUDIO_FILE=$(echo "$CAMPAIGN_CONFIG" | awk -F'\t' '{print $1}')
DTMF_DIGITS=$(echo "$CAMPAIGN_CONFIG" | awk -F'\t' '{print $2}')
NI_DIGIT=$(echo "$CAMPAIGN_CONFIG" | awk -F'\t' '{print $3}')
NI_STATUS=$(echo "$CAMPAIGN_CONFIG" | awk -F'\t' '{print $4}')
WAIT_SECONDS=$(echo "$CAMPAIGN_CONFIG" | awk -F'\t' '{print $5}')
METHOD=$(echo "$CAMPAIGN_CONFIG" | awk -F'\t' '{print $6}')
EXTENSION=$(echo "$CAMPAIGN_CONFIG" | awk -F'\t' '{print $7}')
NO_RESP_ACTION=$(echo "$CAMPAIGN_CONFIG" | awk -F'\t' '{print $8}')

# 3. Check if values changed from initial state
INITIAL_STATE=$(cat /tmp/initial_campaign_state.txt 2>/dev/null || echo "")
STATE_CHANGED="false"
if [ "$CAMPAIGN_CONFIG" != "$INITIAL_STATE" ]; then
    STATE_CHANGED="true"
fi

# 4. Check if Firefox is still running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "state_changed": $STATE_CHANGED,
    "config": {
        "survey_first_audio_file": "$AUDIO_FILE",
        "survey_dtmf_digits": "$DTMF_DIGITS",
        "survey_ni_digit": "$NI_DIGIT",
        "survey_ni_status": "$NI_STATUS",
        "survey_wait_seconds": "$WAIT_SECONDS",
        "survey_method": "$METHOD",
        "survey_extension": "$EXTENSION",
        "survey_no_response_action": "$NO_RESP_ACTION"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="