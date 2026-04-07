#!/bin/bash
echo "=== Exporting configure_external_pacs_node task result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

SCREENSHOT_PATH="/home/ga/Desktop/pacs_node_config.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID_MTIME="false"
SCREENSHOT_SIZE=0

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    # Check if created after task started
    FILE_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        SCREENSHOT_VALID_MTIME="true"
    fi
fi

# Search for Weasis configuration file that was modified during the task
# Weasis saves DICOM node configurations in XML format
CONFIG_FILE_FOUND="false"
NODE_CONFIG_CONTENT=""

# Grep through Weasis config directories for the AE title
MATCHING_FILE=$(grep -rl "REGIONAL_ARCHIVE" /home/ga/.weasis /home/ga/snap/weasis 2>/dev/null | head -1)

if [ -n "$MATCHING_FILE" ]; then
    CONFIG_FILE_FOUND="true"
    # Extract the lines around the match to capture IP/Port attributes
    # The config is typically a single XML line per node or structured block
    NODE_CONFIG_CONTENT=$(grep -i -C 3 "REGIONAL_ARCHIVE" "$MATCHING_FILE" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g')
fi

# Determine if Weasis is still running
APP_RUNNING="false"
if pgrep -f "weasis" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_valid_mtime": $SCREENSHOT_VALID_MTIME,
    "screenshot_size": $SCREENSHOT_SIZE,
    "config_file_found": $CONFIG_FILE_FOUND,
    "node_config_content": "$NODE_CONFIG_CONTENT"
}
EOF

# Safely copy to /tmp for verifier
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="