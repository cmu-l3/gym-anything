#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Read Webmin ACL file
ACL_CONTENT=""
if [ -f "/etc/webmin/webmin.acl" ]; then
    ACL_CONTENT=$(cat /etc/webmin/webmin.acl | base64 -w 0)
fi

# 2. Read Custom Commands config
CUSTOM_CONFIG_CONTENT=""
if [ -f "/etc/webmin/custom/config" ]; then
    CUSTOM_CONFIG_CONTENT=$(cat /etc/webmin/custom/config | base64 -w 0)
fi

# 3. Check service status (did they restart it?)
# We check the ActiveEnterTimestamp to see if it changed after TASK_START
SERVICE_RESTART_TIME=$(systemctl show acmecorp-worker --property=ActiveEnterTimestampMonotonic --value 2>/dev/null || echo "0")
# Note: Monotonic time is hard to compare to unix time without offset calc, 
# so we'll just check if the service is currently running.
SERVICE_ACTIVE=$(systemctl is-active acmecorp-worker 2>/dev/null || echo "inactive")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "acl_content_base64": "$ACL_CONTENT",
    "custom_config_content_base64": "$CUSTOM_CONFIG_CONTENT",
    "service_active": "$SERVICE_ACTIVE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="