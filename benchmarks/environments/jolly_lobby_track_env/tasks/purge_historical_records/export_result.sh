#!/bin/bash
echo "=== Exporting Purge Historical Records result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define paths
EXPORT_FILE="/home/ga/Documents/audit_proof.csv"
TASK_START_FILE="/tmp/task_start_time.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check timestamp
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"
EXPORT_EXISTS="false"
FILE_SIZE="0"

if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if app is running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" >/dev/null 2>&1 || pgrep -f "Lobby" >/dev/null 2>&1; then
    APP_RUNNING="true"
fi

# Read the content of the export file for verification (if it exists)
# We limit to first 100 lines to avoid huge JSON
EXPORT_CONTENT=""
if [ "$EXPORT_EXISTS" = "true" ]; then
    EXPORT_CONTENT=$(head -n 100 "$EXPORT_FILE" | base64 -w 0)
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "export_exists": $EXPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "export_content_b64": "$EXPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="