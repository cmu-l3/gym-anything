#!/bin/bash
echo "=== Exporting Configure Upload Limit Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
echo "Capturing final state..."
take_screenshot /tmp/task_final.png

# 2. Query Artifactory System Configuration API
echo "Querying system configuration..."
CONFIG_RESPONSE=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration")

# 3. Extract File Upload Max Size
# XML format: <fileUploadMaxSize>100</fileUploadMaxSize>
CURRENT_LIMIT=$(echo "$CONFIG_RESPONSE" | grep -oP '(?<=<fileUploadMaxSize>)[^<]+' || echo "not_found")
echo "Current File Upload Limit: $CURRENT_LIMIT"

# 4. Check App State
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "initial_limit": "$(cat /tmp/initial_upload_limit.txt 2>/dev/null || echo 'unknown')",
    "final_limit_raw": "$CURRENT_LIMIT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="