#!/bin/bash
echo "=== Exporting Configure Callback Compliance Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the campaign configuration
echo "Querying Vicidial database for campaign CB_SAFE..."

# We use a complex query to get all fields and format as JSON-like structure or just raw values
# to be parsed by python later. Safer to export to a temp CSV or similar.
# Here we will construct a JSON manually using mysql output.

QUERY="SELECT active, campaign_name, scheduled_callbacks, scheduled_callbacks_alert, scheduled_callbacks_count, scheduled_callbacks_days_limit, max_scheduled_callbacks, agent_only_callbacks_limitation FROM vicidial_campaigns WHERE campaign_id='CB_SAFE'"

# Execute query inside docker
DB_RESULT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -B -N -e "$QUERY" 2>/dev/null || echo "")

# Parse result
# format: active \t name \t sched \t alert \t count \t days \t max \t agent_lim
if [ -n "$DB_RESULT" ]; then
    CAMPAIGN_EXISTS="true"
    # Read tab-separated values
    IFS=$'\t' read -r ACTIVE NAME SCHED ALERT COUNT DAYS MAX AGENT_LIM <<< "$DB_RESULT"
else
    CAMPAIGN_EXISTS="false"
    ACTIVE=""
    NAME=""
    SCHED=""
    ALERT=""
    COUNT=""
    DAYS="0"
    MAX="0"
    AGENT_LIM=""
fi

# Check if Firefox is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "campaign_exists": $CAMPAIGN_EXISTS,
    "campaign_data": {
        "active": "$ACTIVE",
        "name": "$NAME",
        "scheduled_callbacks": "$SCHED",
        "scheduled_callbacks_alert": "$ALERT",
        "scheduled_callbacks_count": "$COUNT",
        "scheduled_callbacks_days_limit": "$DAYS",
        "max_scheduled_callbacks": "$MAX",
        "agent_only_callbacks_limitation": "$AGENT_LIM"
    },
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="