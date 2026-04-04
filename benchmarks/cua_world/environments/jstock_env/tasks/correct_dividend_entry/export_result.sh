#!/bin/bash
echo "=== Exporting correct_dividend_entry results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define paths
DIVIDEND_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/dividendsummary.csv"
FINAL_SCREENSHOT="/tmp/task_final.png"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot "$FINAL_SCREENSHOT" 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root "$FINAL_SCREENSHOT" 2>/dev/null || true

# Check file status
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"
CONTENT=""

if [ -f "$DIVIDEND_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DIVIDEND_FILE")
    FILE_MTIME=$(stat -c %Y "$DIVIDEND_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Read the content for verification
    # We only need the MSFT line really, but small enough to grab all
    CONTENT=$(cat "$DIVIDEND_FILE" | base64 -w 0)
fi

# Check if JStock is running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "file_content_base64": "$CONTENT",
    "app_running": $APP_RUNNING,
    "screenshot_path": "$FINAL_SCREENSHOT"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"