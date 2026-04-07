#!/bin/bash
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if the string exists in the database post-task
mysqldump -u freemed -pfreemed freemed > /tmp/post_task_db.sql 2>/dev/null
PRE_COUNT=$(cat /tmp/pre_task_string_count.txt 2>/dev/null || echo "0")
POST_COUNT=$(grep -c "certified ASL (American Sign Language) interpreter MUST be scheduled" /tmp/post_task_db.sql 2>/dev/null || echo "0")

# 2. Try to specifically locate the note in the pnotes table (most common FreeMED note table)
NOTE_EXISTS="false"
NOTE_SUBJECT=""
NOTE_BODY=""

# Look for recent notes containing our text
NOTE_DATA=$(freemed_query "SELECT id, pttitle, ptbody FROM pnotes WHERE ptbody LIKE '%certified ASL%' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")

if [ -n "$NOTE_DATA" ]; then
    NOTE_EXISTS="true"
    # FreeMED tab-separated output
    NOTE_SUBJECT=$(echo "$NOTE_DATA" | cut -f2 | sed 's/"/\\"/g')
    NOTE_BODY=$(echo "$NOTE_DATA" | cut -f3 | sed 's/"/\\"/g' | tr -d '\n' | cut -c 1-100)
fi

# Determine if Firefox is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pre_task_string_count": $PRE_COUNT,
    "post_task_string_count": $POST_COUNT,
    "note_table_record_exists": $NOTE_EXISTS,
    "note_subject": "$NOTE_SUBJECT",
    "note_body_preview": "$NOTE_BODY",
    "app_was_running": $APP_RUNNING,
    "screenshot_exists": true
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="