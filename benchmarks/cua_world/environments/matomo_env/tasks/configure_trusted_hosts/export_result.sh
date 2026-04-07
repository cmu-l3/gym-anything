#!/bin/bash
echo "=== Exporting Configure Trusted Hosts Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
CONFIG_FILE="/var/www/html/config/config.ini.php"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if file exists
FILE_EXISTS="false"
FILE_SIZE="0"
IS_VALID_PHP="false"
FILE_MODIFIED="false"
CONFIG_CONTENT=""

if [ -f "$CONFIG_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$CONFIG_FILE")
    
    # Check modification time vs task start
    FILE_MTIME=$(stat -c %Y "$CONFIG_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Check for content change vs initial hash
    CURRENT_HASH=$(md5sum "$CONFIG_FILE" | cut -d' ' -f1)
    INITIAL_HASH=$(cat /tmp/initial_config_hash 2>/dev/null || echo "")
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        FILE_MODIFIED="true"
    fi

    # Check syntax (PHP lint)
    # Use the container's PHP to check syntax since host might not have php-cli
    if docker exec matomo-app php -l "$CONFIG_FILE" 2>/dev/null > /dev/null; then
        # If we can't mount it back easily to check, copy it to tmp inside container
        sudo docker cp "$CONFIG_FILE" matomo-app:/tmp/check_syntax.php
        if docker exec matomo-app php -l /tmp/check_syntax.php > /dev/null 2>&1; then
            IS_VALID_PHP="true"
        fi
    fi
    
    # Read content for verifier (base64 to avoid JSON escaping issues)
    CONFIG_CONTENT=$(cat "$CONFIG_FILE" | base64 -w 0)
else
    echo "ERROR: Config file not found at $CONFIG_FILE"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "is_valid_php": $IS_VALID_PHP,
    "config_content_b64": "$CONFIG_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"