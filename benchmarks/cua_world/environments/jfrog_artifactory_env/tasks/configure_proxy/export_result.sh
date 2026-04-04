#!/bin/bash
echo "=== Exporting Configure Proxy Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot (critical for VLM verification)
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Fetch current system configuration XML
# This is the ground truth for verification
echo "Fetching final system configuration..."
CURRENT_CONFIG=$(curl -s -u admin:password http://localhost:8082/artifactory/api/system/configuration)

if [ -z "$CURRENT_CONFIG" ]; then
    echo "ERROR: Failed to retrieve system configuration."
    CONFIG_EXPORT_SUCCESS="false"
else
    CONFIG_EXPORT_SUCCESS="true"
    # Save raw XML for debug/reference (optional)
    echo "$CURRENT_CONFIG" > /tmp/final_config.xml
fi

# Check if Artifactory is running (basic sanity check)
APP_RUNNING=$(pgrep -f "java" > /dev/null && echo "true" || echo "false")

# Create JSON result file
# We embed the XML content into the JSON so the verifier (running on host) 
# can parse it without needing `docker cp` of multiple files.
# We escape quotes in the XML to ensure valid JSON.
ESCAPED_CONFIG=$(echo "$CURRENT_CONFIG" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

# Create JSON in a temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_export_success": $CONFIG_EXPORT_SUCCESS,
    "system_config_xml": $ESCAPED_CONFIG,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="