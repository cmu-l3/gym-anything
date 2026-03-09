#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PPTX_PATH="/home/ga/Documents/Presentations/bia_report.pptx"
ODP_PATH="/home/ga/Documents/Presentations/bia_report.odp"

# Check if files exist and were modified
FILE_EXISTS="false"
FILE_MODIFIED="false"
FINAL_FILE_PATH=""
FILE_SIZE="0"

# Check PPTX first (primary target)
if [ -f "$PPTX_PATH" ]; then
    MTIME=$(stat -c %Y "$PPTX_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_EXISTS="true"
        FILE_MODIFIED="true"
        FINAL_FILE_PATH="$PPTX_PATH"
        FILE_SIZE=$(stat -c %s "$PPTX_PATH" 2>/dev/null || echo "0")
    fi
fi

# If PPTX wasn't modified, check if they saved as ODP
if [ "$FILE_MODIFIED" = "false" ] && [ -f "$ODP_PATH" ]; then
    MTIME=$(stat -c %Y "$ODP_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_EXISTS="true"
        FILE_MODIFIED="true"
        FINAL_FILE_PATH="$ODP_PATH"
        FILE_SIZE=$(stat -c %s "$ODP_PATH" 2>/dev/null || echo "0")
    fi
fi

# If neither modified, just check if PPTX exists (for fail state)
if [ "$FILE_EXISTS" = "false" ] && [ -f "$PPTX_PATH" ]; then
    FILE_EXISTS="true"
    FINAL_FILE_PATH="$PPTX_PATH"
    FILE_SIZE=$(stat -c %s "$PPTX_PATH" 2>/dev/null || echo "0")
fi

# App running check
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "final_file_path": "$FINAL_FILE_PATH",
    "file_size": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Copy result JSON to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="