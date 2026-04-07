#!/bin/bash
set -euo pipefail

echo "=== Exporting customize_login_screen task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Fetch current settings from Rocket.Chat API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

LAYOUT_TITLE=""
LAYOUT_DESCRIPTION=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Fetch title
  TITLE_RESP=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Layout_Login_Title" 2>/dev/null || true)
  
  LAYOUT_TITLE=$(echo "$TITLE_RESP" | jq -r '.value // empty')

  # Fetch description
  DESC_RESP=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Layout_Login_Description" 2>/dev/null || true)
  
  LAYOUT_DESCRIPTION=$(echo "$DESC_RESP" | jq -r '.value // empty')
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_timestamp": $TASK_START,
  "layout_title": "$LAYOUT_TITLE",
  "layout_description": "$LAYOUT_DESCRIPTION"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="