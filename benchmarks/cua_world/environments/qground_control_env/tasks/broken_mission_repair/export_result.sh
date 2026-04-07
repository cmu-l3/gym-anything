#!/bin/bash
echo "=== Exporting broken_mission_repair result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

FIXED_FILE="/home/ga/Documents/QGC/fixed_mission.plan"
ORIGINAL_FILE="/home/ga/Documents/QGC/incoming_mission.plan"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

FILE_FOUND="false"
FILE_SIZE=0
FILE_MTIME=0
MODIFIED_DURING_TASK="false"
PLAN_CONTENT='""'
ORIGINAL_UNTOUCHED="false"

if [ -f "$FIXED_FILE" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(stat -c%s "$FIXED_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$FIXED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    fi
    PLAN_CONTENT=$(cat "$FIXED_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# Check original file was not overwritten (mtime should be < task_start)
if [ -f "$ORIGINAL_FILE" ]; then
    ORIG_MTIME=$(stat -c%Y "$ORIGINAL_FILE" 2>/dev/null || echo "0")
    if [ "$ORIG_MTIME" -lt "$TASK_START" ]; then
        ORIGINAL_UNTOUCHED="true"
    fi
fi

cat > /tmp/task_result.json << JSONEOF
{
    "file_found": $( [ "$FILE_FOUND" = "true" ] && echo "true" || echo "false" ),
    "file_path": "$FIXED_FILE",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "task_start": $TASK_START,
    "modified_during_task": $( [ "$MODIFIED_DURING_TASK" = "true" ] && echo "true" || echo "false" ),
    "original_untouched": $( [ "$ORIGINAL_UNTOUCHED" = "true" ] && echo "true" || echo "false" ),
    "plan_content": $PLAN_CONTENT
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
