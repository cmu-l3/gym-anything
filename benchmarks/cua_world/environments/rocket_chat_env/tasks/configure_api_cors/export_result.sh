#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_api_cors result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Task final screenshot: /tmp/task_final.png"

# Read task start time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Authenticate via API to retrieve settings
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

CORS_ENABLED="false"
CORS_ORIGIN=""
CORS_ENABLED_UPDATED=""
CORS_ORIGIN_UPDATED=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Fetch API_Enable_CORS setting
  ENABLE_CORS_RESP=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/API_Enable_CORS" 2>/dev/null || true)
    
  CORS_ENABLED=$(echo "$ENABLE_CORS_RESP" | jq -r '.value' 2>/dev/null || echo "false")
  CORS_ENABLED_UPDATED=$(echo "$ENABLE_CORS_RESP" | jq -r '._updatedAt' 2>/dev/null || echo "")

  # Fetch API_CORS_Origin setting
  CORS_ORIGIN_RESP=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/API_CORS_Origin" 2>/dev/null || true)
    
  CORS_ORIGIN=$(echo "$CORS_ORIGIN_RESP" | jq -r '.value' 2>/dev/null || echo "")
  CORS_ORIGIN_UPDATED=$(echo "$CORS_ORIGIN_RESP" | jq -r '._updatedAt' 2>/dev/null || echo "")
else
  echo "WARNING: Failed to authenticate via REST API."
fi

# Escape quotes for JSON
CORS_ORIGIN_ESCAPED=$(echo "$CORS_ORIGIN" | sed 's/"/\\"/g')

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "cors_enabled": $CORS_ENABLED,
  "cors_origin": "$CORS_ORIGIN_ESCAPED",
  "cors_enabled_updatedAt": "$CORS_ENABLED_UPDATED",
  "cors_origin_updatedAt": "$CORS_ORIGIN_UPDATED",
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="