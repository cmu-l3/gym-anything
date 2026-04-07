#!/bin/bash
set -euo pipefail

echo "=== Exporting task result: freeze_release_channel ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

ROCKETCHAT_BASE_URL="http://localhost:3000"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="Admin1234!"
CHANNEL_NAME="release-updates"
AGENT_USERNAME="agent.user"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Authenticate to fetch final state
LOGIN_RESPONSE=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ADMIN_USERNAME}\",\"password\":\"${ADMIN_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || echo "{}")

AUTH_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESPONSE" | jq -r '.data.userId // empty' 2>/dev/null || true)

API_SUCCESS="false"
IS_READ_ONLY="false"
ANNOUNCEMENT=""
IS_MODERATOR="false"
CHANNEL_ID=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Get Channel Info
  CHANNEL_INFO=$(curl -sS -X GET \
    -H "X-Auth-Token: ${AUTH_TOKEN}" \
    -H "X-User-Id: ${USER_ID}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=${CHANNEL_NAME}" 2>/dev/null || echo "{}")

  SUCCESS=$(echo "$CHANNEL_INFO" | jq -r '.success // false')
  
  if [ "$SUCCESS" = "true" ]; then
    API_SUCCESS="true"
    CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty')
    IS_READ_ONLY=$(echo "$CHANNEL_INFO" | jq -r '.channel.ro // false')
    ANNOUNCEMENT=$(echo "$CHANNEL_INFO" | jq -r '.channel.announcement // ""')
    
    # Get Roles Info
    ROLES_INFO=$(curl -sS -X GET \
      -H "X-Auth-Token: ${AUTH_TOKEN}" \
      -H "X-User-Id: ${USER_ID}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.roles?roomId=${CHANNEL_ID}" 2>/dev/null || echo "{}")
      
    # Check if agent.user has "moderator" role
    MOD_COUNT=$(echo "$ROLES_INFO" | jq "[.roles[]? | select(.u.username == \"${AGENT_USERNAME}\") | .roles[]? | select(. == \"moderator\")] | length" 2>/dev/null || echo "0")
    
    if [ "$MOD_COUNT" -gt 0 ]; then
      IS_MODERATOR="true"
    fi
  fi
fi

# Get timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "api_success": $API_SUCCESS,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "final_state": {
        "channel_id": "$CHANNEL_ID",
        "read_only": $IS_READ_ONLY,
        "announcement": $(jq -n --arg v "$ANNOUNCEMENT" '$v'),
        "agent_is_moderator": $IS_MODERATOR
    }
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="