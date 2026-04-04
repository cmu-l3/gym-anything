#!/bin/bash
echo "=== Exporting activate_security_lockdown results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Retrieve the full system configuration XML
# This contains offlineMode, anonAccessEnabled, and systemMessage
echo "Retrieving system configuration..."
CONFIG_XML_PATH="/tmp/final_config.xml"
curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration" > "$CONFIG_XML_PATH"

# Check if config retrieval succeeded
if [ -s "$CONFIG_XML_PATH" ]; then
    CONFIG_EXISTS="true"
else
    CONFIG_EXISTS="false"
    echo "WARNING: Failed to retrieve system configuration"
fi

# 2. Functional Check: Verify Anonymous Access is blocked
# Try to access a public endpoint without credentials
echo "Checking anonymous access..."
ANON_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8082/artifactory/api/system/ping")
echo "Anonymous access HTTP code: $ANON_HTTP_CODE"

# 3. Check if Artifactory is running
APP_RUNNING=$(pgrep -f "java" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "config_xml_path": "$CONFIG_XML_PATH",
    "config_exists": $CONFIG_EXISTS,
    "anon_http_code": "$ANON_HTTP_CODE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="