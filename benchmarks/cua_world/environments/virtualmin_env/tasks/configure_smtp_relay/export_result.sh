#!/bin/bash
echo "=== Exporting configure_smtp_relay result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Postfix Configuration
# Get the active 'relayhost' value
RELAYHOST_VAL=$(postconf -h relayhost 2>/dev/null || echo "")

# Get SASL enable flag
SASL_ENABLE_VAL=$(postconf -h smtp_sasl_auth_enable 2>/dev/null || echo "")

# Get the password map file path
SASL_MAPS_VAL=$(postconf -h smtp_sasl_password_maps 2>/dev/null || echo "")
# Clean up 'hash:' prefix if present
MAP_FILE=$(echo "$SASL_MAPS_VAL" | sed 's/^hash://')

# 2. Check Password Map Content
# We need to see if the username and password are in the file.
# Note: In a real scenario, we might decode the hash, but usually the plain text file exists alongside.
MAP_CONTENT=""
MAP_FILE_EXISTS="false"
MAP_FILE_MODIFIED="false"

if [ -n "$MAP_FILE" ] && [ -f "$MAP_FILE" ]; then
    MAP_FILE_EXISTS="true"
    # Read content for verification (safe to expose to verifier, not user)
    MAP_CONTENT=$(cat "$MAP_FILE")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$MAP_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        MAP_FILE_MODIFIED="true"
    fi
fi

# 3. Check Service Status
POSTFIX_RUNNING="false"
if systemctl is-active --quiet postfix; then
    POSTFIX_RUNNING="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "relayhost_value": "$(json_escape "$RELAYHOST_VAL")",
    "sasl_enable_value": "$(json_escape "$SASL_ENABLE_VAL")",
    "sasl_maps_value": "$(json_escape "$SASL_MAPS_VAL")",
    "map_file_exists": $MAP_FILE_EXISTS,
    "map_file_modified": $MAP_FILE_MODIFIED,
    "map_file_content": "$(json_escape "$MAP_CONTENT")",
    "postfix_running": $POSTFIX_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="