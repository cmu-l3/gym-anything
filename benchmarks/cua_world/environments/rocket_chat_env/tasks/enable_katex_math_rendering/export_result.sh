#!/bin/bash
set -euo pipefail

echo "=== Exporting enable_katex_math_rendering task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Log in to API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

KATEX_ENABLED="false"
KATEX_DOLLAR="false"
KATEX_PARENTHESIS="false"
MESSAGE_FOUND="false"
MATCH=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Check Settings
  K_EN_RESP=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_Katex_Enabled" 2>/dev/null)
  K_DOL_RESP=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_Katex_Dollar_Syntax" 2>/dev/null)
  K_PAR_RESP=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_Katex_Parenthesis_Syntax" 2>/dev/null)

  KATEX_ENABLED=$(echo "$K_EN_RESP" | jq -r '.value // false')
  KATEX_DOLLAR=$(echo "$K_DOL_RESP" | jq -r '.value // false')
  KATEX_PARENTHESIS=$(echo "$K_PAR_RESP" | jq -r '.value // false')

  # Search for the message in #general
  CHAN_INFO=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=general" 2>/dev/null)
  CHAN_ID=$(echo "$CHAN_INFO" | jq -r '.channel._id // empty')

  if [ -n "$CHAN_ID" ]; then
    # Search recent messages
    HISTORY=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/channels.history?roomId=${CHAN_ID}&count=20" 2>/dev/null)
    
    # Extract matching message if present
    MATCH=$(echo "$HISTORY" | jq -r '.messages[]? | select(.msg | contains("E = mc^2")) | .msg' | head -n 1)
    
    if [ -n "$MATCH" ]; then
        MESSAGE_FOUND="true"
    fi
  fi
fi

# Convert to valid JSON booleans
[ "$KATEX_ENABLED" = "true" ] && ke_val="true" || ke_val="false"
[ "$KATEX_DOLLAR" = "true" ] && kd_val="true" || kd_val="false"
[ "$KATEX_PARENTHESIS" = "true" ] && kp_val="true" || kp_val="false"
[ "$MESSAGE_FOUND" = "true" ] && mf_val="true" || mf_val="false"

# Use jq to safely format the JSON export (handles text quoting automatically)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
    --argjson ke "$ke_val" \
    --argjson kd "$kd_val" \
    --argjson kp "$kp_val" \
    --argjson mf "$mf_val" \
    --arg mt "${MATCH:-}" \
    '{
        katex_enabled: $ke,
        katex_dollar_syntax: $kd,
        katex_parenthesis_syntax: $kp,
        message_found: $mf,
        message_text: $mt,
        screenshot_path: "/tmp/task_final.png"
    }' > "$TEMP_JSON"

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Results:"
cat /tmp/task_result.json