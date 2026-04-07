#!/bin/bash
echo "=== Exporting create_user_group results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query the Group API to get the final state
echo "Querying group 'compliance-team'..."
GROUP_RESPONSE=$(curl -s -u "$NUXEO_AUTH" \
    -H "Content-Type: application/json" \
    "$NUXEO_URL/api/v1/group/compliance-team")

# Extract HTTP status code separately to check existence
GROUP_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/group/compliance-team")

# 2. Check initial state for anti-gaming
INITIAL_STATE=$(cat /tmp/initial_group_state.txt 2>/dev/null || echo "unknown")

# 3. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Check if Firefox is still running (agent didn't crash it)
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 5. Create JSON result
# We embed the raw API response so the verifier can parse it safely in Python
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_http_status": "$INITIAL_STATE",
    "final_http_status": "$GROUP_HTTP_CODE",
    "group_api_response": $GROUP_RESPONSE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="