#!/bin/bash
set -e
echo "=== Exporting Configure Risk Notification result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# Convert start timestamp to SQL format for query
SQL_START_TIME=$(date -d @$TASK_START '+%Y-%m-%d %H:%M:%S')

# 2. Take final screenshot
take_screenshot /tmp/task_final.png

# 3. Query the database for notifications created/modified during the task
# We dump the output to a JSON structure for the verifier
# We select relevant columns. Note: Schema might vary, so we try to be broad or use specific known columns.
# Common columns in Eramba notifications: name, model, days_before, days_after, threshold, created, modified
echo "Querying database for new notifications..."

# Helper to run MySQL query and output JSON-friendly format
# We use a trick to format MySQL output as JSON lines or CSV to parse later
NEW_NOTIFICATIONS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT name, model, method, days, created, modified FROM notifications \
     WHERE created >= '$SQL_START_TIME' OR modified >= '$SQL_START_TIME';" 2>/dev/null || echo "")

# If the standard table/columns fail, try a fallback (dump all recent rows from 'notifications')
if [ -z "$NEW_NOTIFICATIONS" ]; then
    # Try just dumping everything created recently to debug schema issues
    RAW_DUMP=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
        "SELECT * FROM notifications WHERE created >= '$SQL_START_TIME';" 2>/dev/null || echo "")
else
    RAW_DUMP="$NEW_NOTIFICATIONS"
fi

# 4. Check if Eramba app is still running
APP_RUNNING=$(pgrep -f "httpd" > /dev/null || pgrep -f "apache" > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
# We treat the DB dump as a string to be parsed by python
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
    --arg start "$TASK_START" \
    --arg end "$TASK_END" \
    --arg db_dump "$RAW_DUMP" \
    --arg app_running "$APP_RUNNING" \
    '{
        task_start: $start, 
        task_end: $end, 
        db_notifications_dump: $db_dump, 
        app_was_running: $app_running,
        screenshot_path: "/tmp/task_final.png"
    }' > "$TEMP_JSON"

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="