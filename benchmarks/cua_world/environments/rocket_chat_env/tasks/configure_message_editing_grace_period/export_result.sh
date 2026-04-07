#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_message_editing_grace_period task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve current settings via API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

# Default values in case API calls fail
ALLOW_EDITING="null"
BLOCK_EDIT_MINUTES="null"
KEEP_HISTORY="null"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Fetch Message_AllowEditing
  ALLOW_EDITING=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_AllowEditing" 2>/dev/null | jq -c '.value // false')

  # Fetch Message_AllowEditing_BlockEditInMinutes
  BLOCK_EDIT_MINUTES=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_AllowEditing_BlockEditInMinutes" 2>/dev/null | jq -c '.value // 0')

  # Fetch Message_KeepHistory
  KEEP_HISTORY=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_KeepHistory" 2>/dev/null | jq -c '.value // false')
else
  echo "ERROR: Failed to authenticate for data export."
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "settings": {
    "Message_AllowEditing": $ALLOW_EDITING,
    "Message_AllowEditing_BlockEditInMinutes": $BLOCK_EDIT_MINUTES,
    "Message_KeepHistory": $KEEP_HISTORY
  },
  "screenshot_path": "/tmp/task_final.png",
  "timestamp": "$(date +%s)"
}
EOF

# Move securely to prevent permission issues
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="