#!/bin/bash
echo "=== Exporting classify_sensitive_data_reqs results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_DIR="/home/ga/Documents/ReqView/classify_sensitive_project"
SRS_FILE="$PROJECT_DIR/documents/SRS.json"

# Check file modification
FILE_MODIFIED="false"
if [ -f "$SRS_FILE" ]; then
    SRS_MTIME=$(stat -c %Y "$SRS_FILE" 2>/dev/null || echo "0")
    if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# App running check
APP_RUNNING=$(pgrep -f "reqview" > /dev/null && echo "true" || echo "false")

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "srs_modified": $FILE_MODIFIED,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="