#!/bin/bash
set -euo pipefail

echo "=== Exporting Canned Responses Task Result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png

# Task metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Authenticate to fetch results
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USERID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

# Default empty response list
CANNED_JSON='{"cannedResponses": []}'

if [ -n "$TOKEN" ] && [ -n "$USERID" ]; then
  # Fetch canned responses
  FETCH_RESP=$(curl -sS -H "X-Auth-Token: $TOKEN" -H "X-User-Id: $USERID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/canned-responses" 2>/dev/null)
  
  # Validate response is JSON
  if echo "$FETCH_RESP" | jq -e . >/dev/null 2>&1; then
    CANNED_JSON="$FETCH_RESP"
  else
    echo "WARNING: API returned invalid JSON"
  fi
else
  echo "WARNING: Failed to authenticate for export"
fi

# Check if browser was running
APP_RUNNING="false"
if pgrep -f "firefox" >/dev/null; then
  APP_RUNNING="true"
fi

# Compile result to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "app_was_running": $APP_RUNNING,
  "screenshot_path": "/tmp/task_final.png",
  "api_data": $CANNED_JSON
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Data saved to /tmp/task_result.json"