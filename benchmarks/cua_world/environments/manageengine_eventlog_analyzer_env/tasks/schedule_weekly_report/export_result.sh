#!/bin/bash
# Export script for schedule_weekly_report task
echo "=== Exporting Schedule Weekly Report results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Database Verification
# Check counts again
CURRENT_COUNT_1=$(ela_db_query "SELECT COUNT(*) FROM scheduledreports;" 2>/dev/null || echo "0")
CURRENT_COUNT_2=$(ela_db_query "SELECT COUNT(*) FROM task_schedule WHERE task_type ILIKE '%report%';" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_scheduled_count.txt 2>/dev/null || echo "0")

# Determine if count increased
COUNT_INCREASED="false"
if [ "$CURRENT_COUNT_1" -gt "$INITIAL_COUNT" ] || [ "$CURRENT_COUNT_2" -gt "$INITIAL_COUNT" ]; then
    COUNT_INCREASED="true"
fi

# Try to fetch details of the most recently added schedule
# Note: Schema is hypothetical based on common ELA structure, robustness provided by broad selection
LATEST_SCHEDULE_DETAILS=$(ela_db_query "
    SELECT * FROM scheduledreports ORDER BY schedule_id DESC LIMIT 1;
" 2>/dev/null)

if [ -z "$LATEST_SCHEDULE_DETAILS" ]; then
    LATEST_SCHEDULE_DETAILS=$(ela_db_query "
        SELECT * FROM task_schedule WHERE task_type ILIKE '%report%' ORDER BY created_time DESC LIMIT 1;
    " 2>/dev/null)
fi

echo "Latest schedule DB entry: $LATEST_SCHEDULE_DETAILS"

# 2. API Verification (Alternative signal)
# Log in and check scheduled reports endpoint
COOKIE_JAR=$(ela_login)
API_RESPONSE=$(curl -s -b "$COOKIE_JAR" "http://localhost:8095/event/api/scheduledReports" 2>/dev/null || echo "{}")

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_db_count": $INITIAL_COUNT,
    "current_db_count_1": $CURRENT_COUNT_1,
    "current_db_count_2": $CURRENT_COUNT_2,
    "count_increased": $COUNT_INCREASED,
    "latest_db_entry": "$(echo "$LATEST_SCHEDULE_DETAILS" | sed 's/"/\\"/g' | tr -d '\n')",
    "api_response_length": ${#API_RESPONSE},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="