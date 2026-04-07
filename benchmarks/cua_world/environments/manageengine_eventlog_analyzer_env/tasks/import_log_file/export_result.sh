#!/bin/bash
# Export results for "import_log_file" task

echo "=== Exporting Import Log File Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/import_log_file_final.png

# 2. Check Database for New Events
INITIAL_COUNT=$(cat /tmp/initial_event_count.txt 2>/dev/null || echo "0")

# Query current count
CURRENT_COUNT=$(ela_db_query "SELECT count(*) FROM Component_Event_Log" 2>/dev/null || echo "0")
if [ "$CURRENT_COUNT" = "0" ]; then
    CURRENT_COUNT=$(ela_db_query "SELECT count(*) FROM EventLog" 2>/dev/null || echo "0")
fi

# Calculate increase
EVENT_INCREASE=$((CURRENT_COUNT - INITIAL_COUNT))

# Check for specific keywords in recent events (stronger verification)
# We search for 'pam_unix' which is common in auth.log
KEYWORD_FOUND="false"
# Try querying for content. Note: SQL syntax depends on DB (PostgreSQL).
# We limit to checks if we can execute them.
KEYWORD_CHECK=$(ela_db_query "SELECT count(*) FROM Component_Event_Log WHERE MESSAGE LIKE '%pam_unix%'" 2>/dev/null || echo "0")
# If table doesn't exist or query fails, we rely on total count and VLM.

echo "Events: Initial=$INITIAL_COUNT, Current=$CURRENT_COUNT, Increase=$EVENT_INCREASE"

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_event_count": $INITIAL_COUNT,
    "current_event_count": $CURRENT_COUNT,
    "event_count_increase": $EVENT_INCREASE,
    "keyword_check_count": ${KEYWORD_CHECK:-0},
    "log_file_path": "/home/ga/log_samples/auth.log",
    "screenshot_path": "/tmp/import_log_file_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="