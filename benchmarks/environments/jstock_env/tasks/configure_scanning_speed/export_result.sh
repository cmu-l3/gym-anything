#!/bin/bash
echo "=== Exporting configure_scanning_speed results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if application is still running
APP_RUNNING="false"
if pgrep -f "jstock.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# 2. Find the options configuration file
# JStock config structure can vary, so we search for it
CONFIG_FILE=$(find /home/ga/.jstock/1.0.7 -name "options.xml" -o -name "*option*.xml" | head -n 1)

CONFIG_EXISTS="false"
CONFIG_MODIFIED_DURING_TASK="false"
CONFIG_CONTENT=""
SCANNING_SPEED_FOUND=""

if [ -f "$CONFIG_FILE" ]; then
    CONFIG_EXISTS="true"
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED_DURING_TASK="true"
    fi
    
    # Read content for verification (embedded in JSON)
    # We limit size just in case, though config files are small
    CONFIG_CONTENT=$(cat "$CONFIG_FILE" | head -c 10000)
    
    # Simple grep check for debugging purposes in logs
    if grep -q "SLOW" "$CONFIG_FILE"; then
        SCANNING_SPEED_FOUND="SLOW"
    elif grep -q "60000" "$CONFIG_FILE"; then
        SCANNING_SPEED_FOUND="60000"
    elif grep -q "NORMAL" "$CONFIG_FILE"; then
        SCANNING_SPEED_FOUND="NORMAL"
    elif grep -q "30000" "$CONFIG_FILE"; then
        SCANNING_SPEED_FOUND="30000"
    fi
else
    echo "WARNING: Could not find JStock options configuration file"
fi

# 3. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "config_file_found": $CONFIG_EXISTS,
    "config_file_path": "$CONFIG_FILE",
    "config_modified_during_task": $CONFIG_MODIFIED_DURING_TASK,
    "scanning_speed_value_found": "$SCANNING_SPEED_FOUND",
    "config_content_snippet": $(jq -R -s '.' <<< "$CONFIG_CONTENT"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "Found config: $CONFIG_FILE"
echo "Modified during task: $CONFIG_MODIFIED_DURING_TASK"
echo "Value found: $SCANNING_SPEED_FOUND"

echo "=== Export complete ==="