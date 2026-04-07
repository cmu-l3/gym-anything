#!/bin/bash
echo "=== Exporting task results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if app is running
APP_RUNNING=$(pgrep -f "reqview" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We don't need to manually export JSON here because the verifier 
# will read the source files directly using copy_from_env.
# But we'll create a simple result metadata file.

PROJECT_DIR="/home/ga/Documents/ReqView/messy_project"
SRS_PATH="$PROJECT_DIR/documents/SRS.json"
FILE_MODIFIED="false"

if [ -f "$SRS_PATH" ]; then
    MTIME=$(stat -c %Y "$SRS_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "file_modified": $FILE_MODIFIED,
    "srs_path": "$SRS_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result metadata saved."
echo "=== Export complete ==="