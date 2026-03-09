#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Optimize Presentation Result ==="

TARGET_FILE="/home/ga/Documents/Presentations/product_showcase_heavy.odp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot of the UI
take_screenshot /tmp/task_final.png

# Check file status
FILE_EXISTS="false"
FILE_SIZE_BYTES=0
FILE_MODIFIED="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c%s "$TARGET_FILE")
    FILE_MTIME=$(stat -c%Y "$TARGET_FILE")
    
    # Check if modified after start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "soffice" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "file_modified": $FILE_MODIFIED,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissive rights
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "Final Size: $((FILE_SIZE_BYTES / 1024)) KB"
echo "=== Export Complete ==="