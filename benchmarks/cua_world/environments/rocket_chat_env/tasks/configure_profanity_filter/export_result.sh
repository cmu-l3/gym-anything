#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting configure_profanity_filter task results ==="

ROCKETCHAT_BASE_URL="http://localhost:3000"
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Authenticate for verification queries
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || echo "{}")

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

SETTINGS_ENABLED="unknown"
SETTINGS_LIST=""
MSGS_JSON="[]"
MSG_COUNT_DIFF=0

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  HEADERS=(-H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" -H "Content-Type: application/json")

  # Query final settings
  SETTINGS_ENABLED=$(curl -sS -X GET "${HEADERS[@]}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_AllowBadWordsFilter" 2>/dev/null | jq -r '.value // "false"')
    
  SETTINGS_LIST=$(curl -sS -X GET "${HEADERS[@]}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Message_BadWordsFilterList" 2>/dev/null | jq -r '.value // ""')

  # Query #general messages
  # We fetch last 10 messages to find the test message
  MSGS_JSON=$(curl -sS -X GET "${HEADERS[@]}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.history?roomName=general&count=10" 2>/dev/null | jq '.messages // []')

  # Calculate message diff
  INITIAL_COUNT=$(cat /tmp/initial_general_msg_count.txt 2>/dev/null || echo "0")
  # Note: channels.history count param limits return, not total count. 
  # We rely on checking if *new* messages exist in the returned list that match criteria.
  # For simplicity in JSON, we'll just pass the whole message list to Python to parse.
fi

# Escape quotes for JSON
SETTINGS_LIST_ESCAPED=$(echo "$SETTINGS_LIST" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "settings_enabled": "$SETTINGS_ENABLED",
    "settings_list": "$SETTINGS_LIST_ESCAPED",
    "recent_messages": $MSGS_JSON,
    "initial_msg_count": $(cat /tmp/initial_general_msg_count.txt 2>/dev/null || echo "0"),
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="