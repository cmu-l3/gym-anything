#!/bin/bash
# Export script for Schedule Automated Report task
# Saves verification data to JSON file

echo "=== Exporting Schedule Automated Report Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Define timetrex_query fallback if not loaded
if ! type timetrex_query &>/dev/null; then
    timetrex_query() {
        docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "$1" 2>/dev/null | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//'
    }
fi

# Ensure containers are running
if type ensure_docker_containers &>/dev/null; then
    ensure_docker_containers
else
    docker ps | grep -q timetrex || docker start timetrex timetrex-postgres 2>/dev/null || true
    sleep 3
fi

# Take final screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_end_screenshot.png
else
    DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true
fi

# Get current schedule count
CURRENT_COUNT=$(timetrex_query "SELECT COUNT(*) FROM report_schedule WHERE deleted=0" | tr -d '\n\r ')
INITIAL_COUNT=$(cat /tmp/initial_report_count 2>/dev/null || echo "0")

if [ -z "$CURRENT_COUNT" ]; then
    CURRENT_COUNT="0"
fi

echo "Report schedule count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Initialize variables
SCHEDULE_FOUND="false"
SCHEDULE_ID=""
SCHEDULE_NAME=""
SCHEDULE_EMAIL=""
SCHEDULE_FREQ=""

# Look for new schedules created during the task
if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    # Get the ID of the most recently created report schedule
    NEW_ID=$(timetrex_query "SELECT id FROM report_schedule WHERE deleted=0 ORDER BY created_date DESC LIMIT 1" | tr -d '\n\r ')
    
    if [ -n "$NEW_ID" ]; then
        SCHEDULE_FOUND="true"
        SCHEDULE_ID="$NEW_ID"
        SCHEDULE_NAME=$(timetrex_query "SELECT name FROM report_schedule WHERE id='$NEW_ID'")
        
        # Depending on the exact TimeTrex version, the email column could be 'to_address' or 'email_address'
        SCHEDULE_EMAIL=$(timetrex_query "SELECT to_address FROM report_schedule WHERE id='$NEW_ID'")
        if [ -z "$SCHEDULE_EMAIL" ] || [[ "$SCHEDULE_EMAIL" == *"does not exist"* ]]; then
            SCHEDULE_EMAIL=$(timetrex_query "SELECT email_address FROM report_schedule WHERE id='$NEW_ID'")
        fi
        
        SCHEDULE_FREQ=$(timetrex_query "SELECT frequency_id FROM report_schedule WHERE id='$NEW_ID'" | tr -d '\n\r ')
        
        echo "New report schedule found: ID=$SCHEDULE_ID, Name='$SCHEDULE_NAME', Email='$SCHEDULE_EMAIL', FreqID='$SCHEDULE_FREQ'"
    fi
else
    echo "No new report schedules found in database."
    
    # Anti-schema-change fallback: Search the raw database dump for the target email address
    # This guarantees we find it if the agent successfully entered the email anywhere
    echo "Performing raw database search for target email..."
    RAW_EMAIL_DUMP=$(docker exec timetrex-postgres pg_dump -U timetrex -d timetrex --data-only 2>/dev/null | grep -i "supervisor@greenleafwellness.com" | head -1)
    
    if [ -n "$RAW_EMAIL_DUMP" ]; then
        echo "Target email found via raw database search!"
        SCHEDULE_FOUND="true"
        SCHEDULE_EMAIL="supervisor@greenleafwellness.com"
        SCHEDULE_NAME="Unknown (found via raw fallback)"
    fi
fi

# Clean and escape strings for JSON formatting
SCHEDULE_NAME_ESCAPED=$(echo "$SCHEDULE_NAME" | sed 's/"/\\"/g' | tr -d '\n\r')
SCHEDULE_EMAIL_ESCAPED=$(echo "$SCHEDULE_EMAIL" | sed 's/"/\\"/g' | tr -d '\n\r')
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Write results to JSON
TEMP_JSON=$(mktemp /tmp/schedule_report_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "schedule_found": $SCHEDULE_FOUND,
    "schedule_name": "$SCHEDULE_NAME_ESCAPED",
    "schedule_email": "$SCHEDULE_EMAIL_ESCAPED",
    "schedule_freq": "$SCHEDULE_FREQ",
    "task_start_timestamp": "$TASK_START",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location safely
rm -f /tmp/schedule_report_result.json 2>/dev/null || sudo rm -f /tmp/schedule_report_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/schedule_report_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/schedule_report_result.json
chmod 666 /tmp/schedule_report_result.json 2>/dev/null || sudo chmod 666 /tmp/schedule_report_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Exported Result:"
cat /tmp/schedule_report_result.json
echo ""
echo "=== Export Complete ==="