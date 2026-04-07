#!/bin/bash
echo "=== Exporting structure_scan_silo_inspection result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

PLAN_FILE="/home/ga/Documents/QGC/silo_inspection.plan"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

FILE_FOUND="false"
FILE_SIZE=0
FILE_MTIME=0
MODIFIED_DURING_TASK="false"
PLAN_CONTENT='""'

if [ -f "$PLAN_FILE" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(stat -c%s "$PLAN_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$PLAN_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    fi
    # Read plan content (escape for JSON embedding — will be unescaped in verifier)
    PLAN_CONTENT=$(cat "$PLAN_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

cat > /tmp/task_result.json << JSONEOF
{
    "file_found": $( [ "$FILE_FOUND" = "true" ] && echo "true" || echo "false" ),
    "file_path": "$PLAN_FILE",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "task_start": $TASK_START,
    "modified_during_task": $( [ "$MODIFIED_DURING_TASK" = "true" ] && echo "true" || echo "false" ),
    "plan_content": $PLAN_CONTENT
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="