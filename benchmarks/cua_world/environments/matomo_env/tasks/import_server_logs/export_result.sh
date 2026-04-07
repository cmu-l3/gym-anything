#!/bin/bash
# Export script for Import Server Logs task

echo "=== Exporting Import Server Logs Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Get Database Metrics
INITIAL_VISITS=$(cat /tmp/initial_visit_count.txt 2>/dev/null || echo "0")
CURRENT_VISITS=$(matomo_query "SELECT COUNT(*) FROM matomo_log_visit WHERE idsite=1")

# Get count of actions (pageviews)
CURRENT_ACTIONS=$(matomo_query "SELECT COUNT(*) FROM matomo_log_link_visit_action WHERE idsite=1")

# Check for visits with appropriate timestamps (last 8 days)
# We expect the logs to be recent
RECENT_VISITS=$(matomo_query "SELECT COUNT(*) FROM matomo_log_visit WHERE idsite=1 AND visit_first_action_time >= DATE_SUB(NOW(), INTERVAL 8 DAY)")

# Check if browser/OS info was parsed (indicates proper import tool usage vs raw SQL insert)
PARSED_USER_AGENTS=$(matomo_query "SELECT COUNT(*) FROM matomo_log_visit WHERE idsite=1 AND config_browser_name IS NOT NULL AND config_browser_name != ''")

echo "Visits: Initial=$INITIAL_VISITS, Current=$CURRENT_VISITS"
echo "Actions: $CURRENT_ACTIONS"
echo "Recent Visits: $RECENT_VISITS"
echo "Parsed UA Visits: $PARSED_USER_AGENTS"

# 2. Check Result File
RESULT_FILE_PATH="/home/ga/Documents/access_logs/import_result.txt"
RESULT_FILE_EXISTS="false"
RESULT_FILE_CONTENT=""

if [ -f "$RESULT_FILE_PATH" ]; then
    RESULT_FILE_EXISTS="true"
    RESULT_FILE_CONTENT=$(cat "$RESULT_FILE_PATH" | tr -d '[:space:]') # Strip whitespace
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/import_logs_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_visits": ${INITIAL_VISITS:-0},
    "current_visits": ${CURRENT_VISITS:-0},
    "current_actions": ${CURRENT_ACTIONS:-0},
    "recent_visits": ${RECENT_VISITS:-0},
    "parsed_user_agents": ${PARSED_USER_AGENTS:-0},
    "result_file_exists": $RESULT_FILE_EXISTS,
    "result_file_content": "$RESULT_FILE_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save and permission
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="