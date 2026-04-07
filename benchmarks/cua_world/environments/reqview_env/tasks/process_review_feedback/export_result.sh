#!/bin/bash
echo "=== Exporting Process Review Feedback results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (before closing, to show state)
take_screenshot /tmp/task_final.png

# 2. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Gracefully close ReqView to ensure JSON flush
# (ReqView autosaves, but clean exit is safer for file consistency)
wmctrl -c "ReqView" 2>/dev/null || true
sleep 2
pkill -f "reqview" 2>/dev/null || true

# 4. Check File Modification
PROJECT_SRS="/home/ga/Documents/ReqView/review_feedback_project/documents/SRS.json"
FILE_MODIFIED="false"
if [ -f "$PROJECT_SRS" ]; then
    SRS_MTIME=$(stat -c %Y "$PROJECT_SRS" 2>/dev/null || echo "0")
    if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 5. Generate Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "srs_path": "$PROJECT_SRS"
}
EOF

echo "Result exported to /tmp/task_result.json"