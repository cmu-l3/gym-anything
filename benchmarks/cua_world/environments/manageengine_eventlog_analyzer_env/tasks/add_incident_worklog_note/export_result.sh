#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture VLM trajectory frames (handled by framework, but we ensure final state is good)
sleep 2

# Query the database for the worklog note
# We look for the note text in the AlertWorkLog or similar tables
# Note: Table names might vary by version, so we try a few common ManageEngine schemas
# or simply search the text column if we can find the table.

echo "Querying database for worklog notes..."

# We construct a query to find the specific note text
# Common table for notes/worklogs in ELA: AlertWorkLog, WorkFlowDetails, or similar.
# We'll try to select columns that contain the comment.

QUERY="SELECT * FROM AlertWorkLog WHERE COMMENTS LIKE '%Initial triage%';"
DB_RESULT=$(ela_db_query "$QUERY")

# If empty, try another common table name for notes
if [ -z "$DB_RESULT" ]; then
    QUERY="SELECT * FROM AM_AlertWorkLog WHERE COMMENTS LIKE '%Initial triage%';"
    DB_RESULT=$(ela_db_query "$QUERY")
fi

# If still empty, try searching broadly in a dump (less elegant but robust)
if [ -z "$DB_RESULT" ]; then
     echo "Direct query empty, trying broad search..."
     # This is a fallback; usually the table is AlertWorkLog
fi

# Verify if the alert itself exists (to confirm environment worked)
ALERT_CHECK=$(ela_db_query "SELECT * FROM AlertDetails WHERE MESSAGE LIKE '%CORE_DUMP%';")

# Save results to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_note_record": "$(echo "$DB_RESULT" | sed 's/"/\\"/g')",
    "db_alert_record": "$(echo "$ALERT_CHECK" | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="