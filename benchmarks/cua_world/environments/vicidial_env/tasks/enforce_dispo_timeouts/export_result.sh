#!/bin/bash
echo "=== Exporting Enforce Dispo Timeouts Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ==============================================================================
# DATABASE EXTRACTION
# We extract the specific rows for the requested campaign and status
# ==============================================================================

# Helper to run MySQL query inside container and return JSON
# Uses jq to format if available, or python fallback if complex
# For simplicity, we'll fetch raw values and build JSON in bash or python

# fetch_campaign_config
CAMPAIGN_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT campaign_id, campaign_name, active, dial_method, auto_dial_level, dispo_screen_time_limit, dispo_screen_time_limit_status, wrapup_seconds, agent_pause_after_each_call \
     FROM vicidial_campaigns WHERE campaign_id='FASTTRACK'" \
    | awk -F'\t' '{printf "{\"id\":\"%s\", \"name\":\"%s\", \"active\":\"%s\", \"dial_method\":\"%s\", \"level\":\"%s\", \"dispo_limit\":\"%s\", \"dispo_status\":\"%s\", \"wrapup\":\"%s\", \"pause_after\":\"%s\"}", $1, $2, $3, $4, $5, $6, $7, $8, $9}' \
    || echo "null")

if [ -z "$CAMPAIGN_JSON" ]; then CAMPAIGN_JSON="null"; fi

# fetch_status_config
STATUS_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT status, status_name, selectable, human_answered \
     FROM vicidial_campaign_statuses WHERE campaign_id='FASTTRACK' AND status='DISPTO'" \
    | awk -F'\t' '{printf "{\"status\":\"%s\", \"name\":\"%s\", \"selectable\":\"%s\", \"human_answered\":\"%s\"}", $1, $2, $3, $4}' \
    || echo "null")

if [ -z "$STATUS_JSON" ]; then STATUS_JSON="null"; fi

# Check if application (Firefox) is running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then APP_RUNNING="true"; fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "campaign": $CAMPAIGN_JSON,
    "status": $STATUS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported Data:"
cat /tmp/task_result.json
echo "=== Export Complete ==="