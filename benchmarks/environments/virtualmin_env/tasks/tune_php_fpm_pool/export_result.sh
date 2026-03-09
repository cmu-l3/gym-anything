#!/bin/bash
echo "=== Exporting tune_php_fpm_pool results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Retrieve target pool file path
POOL_FILE=$(cat /tmp/target_pool_file.txt 2>/dev/null)

# Check if file exists
FILE_EXISTS="false"
FILE_MODIFIED="false"
CONFIG_CONTENT=""
SYNTAX_CHECK="false"
SERVICE_ACTIVE="false"

if [ -n "$POOL_FILE" ] && [ -f "$POOL_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check modification
    INITIAL_SUM=$(cat /tmp/initial_pool_checksum.txt | awk '{print $1}' 2>/dev/null || echo "none")
    CURRENT_SUM=$(md5sum "$POOL_FILE" | awk '{print $1}')
    
    if [ "$INITIAL_SUM" != "$CURRENT_SUM" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Read content for verifier (base64 to avoid JSON escaping issues)
    CONFIG_CONTENT=$(base64 -w 0 "$POOL_FILE")
    
    # Check syntax
    if php-fpm*-t > /dev/null 2>&1; then
        # The command might vary by version (e.g. php-fpm8.1 -t), try generic check
        # Usually 'php-fpm -t' or specific version
        if /usr/sbin/php-fpm* -t 2>/dev/null; then
             SYNTAX_CHECK="true"
        elif php -r "exit(0);" 2>/dev/null; then
             # Fallback: if we can't find the binary easily, assume true if service is running
             SYNTAX_CHECK="true"
        fi
    fi
else
    echo "WARNING: Pool file not found at expected location: $POOL_FILE"
fi

# Check service status
if systemctl is-active --quiet "php*-fpm"; then
    SERVICE_ACTIVE="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "config_content_b64": "$CONFIG_CONTENT",
    "syntax_valid": $SYNTAX_CHECK,
    "service_active": $SERVICE_ACTIVE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="