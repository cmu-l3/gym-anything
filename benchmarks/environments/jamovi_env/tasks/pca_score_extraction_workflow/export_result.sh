#!/bin/bash
echo "=== Exporting PCA Workflow Results ==="

# 1. Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check Paths
PROJECT_PATH="/home/ga/Documents/Jamovi/PCA_Workflow.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/neuroticism_age_corr.txt"

# 3. Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE="0"
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_EXISTS="true"
        PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
    fi
fi

# 4. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_EXISTS="true"
        REPORT_CONTENT=$(cat "$REPORT_PATH" | tr -d '\n\r' | awk '{$1=$1};1')
    fi
fi

# 5. Take final screenshot for VLM verification
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_path": "$PROJECT_PATH",
    "project_size": $PROJECT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_content": "$REPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Move JSON to export location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json