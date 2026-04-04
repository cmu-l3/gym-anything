#!/bin/bash
echo "=== Exporting High Altitude Performance Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state visual
take_screenshot /tmp/task_final.png

# 2. Gather file info
PROJECT_FILE="/home/ga/Documents/projects/altitude_study.wpa"
REPORT_FILE="/home/ga/Documents/projects/altitude_report.txt"

# Check project file
PROJECT_EXISTS="false"
PROJECT_SIZE="0"
if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_FILE")
fi

# Check report file
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Read content, limit length to avoid massive JSON
    REPORT_CONTENT=$(head -n 20 "$REPORT_FILE" | base64 -w 0)
fi

# Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"
if [ "$PROJECT_EXISTS" = "true" ]; then
    FILE_MTIME=$(stat -c %Y "$PROJECT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Create Result JSON
# We treat the .wpa file as text (XML) for the verifier to parse, 
# but since it might be large, we'll let the verifier read it directly via copy_from_env.
# We only export metadata here.

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "project_exists": $PROJECT_EXISTS,
    "project_path": "$PROJECT_FILE",
    "project_size": $PROJECT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Save result safely
chmod 666 /tmp/task_result.json

echo "Export complete. Result summary:"
cat /tmp/task_result.json