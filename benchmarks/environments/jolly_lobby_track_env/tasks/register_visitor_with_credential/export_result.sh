#!/bin/bash
echo "=== Exporting register_visitor_with_credential result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Paths
EXPECTED_PATH="/home/ga/Documents/security_checkin.csv"
ALTERNATE_PATH="/home/ga/Documents/security_checkin.txt"
WINE_DOCS="/home/ga/.wine/drive_c/users/ga/Documents/security_checkin.csv"

# Check if output file exists (agent might save to Linux path or Wine path)
OUTPUT_EXISTS="false"
ACTUAL_PATH=""
FILE_SIZE="0"
FILE_CONTENT=""

# Check possible locations
if [ -f "$EXPECTED_PATH" ]; then
    ACTUAL_PATH="$EXPECTED_PATH"
elif [ -f "$ALTERNATE_PATH" ]; then
    ACTUAL_PATH="$ALTERNATE_PATH"
elif [ -f "$WINE_DOCS" ]; then
    ACTUAL_PATH="$WINE_DOCS"
# Check for any CSV in Documents if exact name wasn't used
elif compgen -G "/home/ga/Documents/*.csv" > /dev/null; then
    ACTUAL_PATH=$(ls -t /home/ga/Documents/*.csv | head -1)
fi

# Analyze the file if found
if [ -n "$ACTUAL_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$ACTUAL_PATH" 2>/dev/null || echo "0")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$ACTUAL_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Read content (first 50 lines) for verification
    # Use base64 to safely transport content in JSON
    FILE_CONTENT=$(head -n 50 "$ACTUAL_PATH" | base64 -w 0)
else
    FILE_CREATED_DURING_TASK="false"
fi

# Check if application is still running
APP_RUNNING=$(pgrep -f "LobbyTrack" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "actual_path": "$ACTUAL_PATH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "file_content_b64": "$FILE_CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="