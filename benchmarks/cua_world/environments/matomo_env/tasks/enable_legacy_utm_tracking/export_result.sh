#!/bin/bash
# Export script for Enable Legacy UTM Tracking task

echo "=== Exporting Enable Legacy UTM Tracking Result ==="
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Path to config file inside container
CONFIG_PATH="/var/www/html/config/config.ini.php"

# Check if Matomo container is running
MATOMO_RUNNING="false"
if docker ps | grep -q matomo-app; then
    MATOMO_RUNNING="true"
fi

# Extract the config file content
CONFIG_CONTENT=""
CONFIG_MODIFIED_TS="0"
FILE_EXISTS="false"

if [ "$MATOMO_RUNNING" = "true" ]; then
    # Check if file exists
    if docker exec matomo-app test -f "$CONFIG_PATH"; then
        FILE_EXISTS="true"
        # Get content (base64 encoded to avoid JSON escaping issues)
        CONFIG_CONTENT=$(docker exec matomo-app cat "$CONFIG_PATH" | base64 -w 0)
        # Get modification timestamp (stat in container)
        CONFIG_MODIFIED_TS=$(docker exec matomo-app stat -c %Y "$CONFIG_PATH" 2>/dev/null || echo "0")
    fi
fi

# Determine if file was modified during task
FILE_MODIFIED_DURING_TASK="false"
if [ "$CONFIG_MODIFIED_TS" -gt "$TASK_START" ]; then
    FILE_MODIFIED_DURING_TASK="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "config_content_base64": "$CONFIG_CONTENT",
    "matomo_running": $MATOMO_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="