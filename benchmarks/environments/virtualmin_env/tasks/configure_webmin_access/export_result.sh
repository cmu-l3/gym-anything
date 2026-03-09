#!/bin/bash
echo "=== Exporting configure_webmin_access results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONFIG_FILE="/etc/webmin/miniserv.conf"

# 1. Check if config file was modified
CONFIG_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
    MODIFIED="true"
else
    MODIFIED="false"
fi

# 2. Check for lockout (Connectivity check)
# Try to access Webmin from localhost
HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" https://localhost:10000/ || echo "000")

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "302" ]; then
    LOCKED_OUT="false"
else
    LOCKED_OUT="true"
fi

# 3. Capture config content for verification
# We copy it to a temp file that the verifier can retrieve
cp "$CONFIG_FILE" /tmp/miniserv.conf.result
chmod 644 /tmp/miniserv.conf.result

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config_modified": $MODIFIED,
    "locked_out": $LOCKED_OUT,
    "http_status": "$HTTP_STATUS",
    "config_path": "/tmp/miniserv.conf.result",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="