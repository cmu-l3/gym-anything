#!/bin/bash
set -euo pipefail

echo "=== Exporting investigate_concurrent_sessions results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/rogue_ips.txt"

# Check the output file
FILE_EXISTS="false"
FILE_MTIME="0"
FILE_SIZE="0"
FILE_CONTENT=""

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Read up to 1000 bytes and escape safely for JSON
    FILE_CONTENT=$(head -c 1000 "$TARGET_FILE" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))')
else
    # default empty json string
    FILE_CONTENT='""'
fi

APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result using a temporary file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_mtime": $FILE_MTIME,
    "file_size": $FILE_SIZE,
    "file_content": $FILE_CONTENT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/final_screenshot.png"
}
EOF

# Ensure appropriate permissions and move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="