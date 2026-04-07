#!/bin/bash
echo "=== Exporting storage management results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get current storage configuration via API
TOKEN=$(get_nx_token)
SERVER_ID=$(get_server_id)

if [ -n "$SERVER_ID" ] && [ -n "$TOKEN" ]; then
    CURRENT_STORAGES=$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
        "https://localhost:7001/rest/v1/servers/${SERVER_ID}/storages" \
        --max-time 15 2>/dev/null || echo "[]")
else
    CURRENT_STORAGES="[]"
fi

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_storage_count.txt 2>/dev/null || echo "0")

# Check if Firefox is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_storage_count": $INITIAL_COUNT,
    "current_storages": $CURRENT_STORAGES,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="