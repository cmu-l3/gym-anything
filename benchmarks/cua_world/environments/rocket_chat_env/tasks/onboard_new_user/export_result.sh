#!/bin/bash
set -euo pipefail

echo "=== Exporting onboard_new_user task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_MEMBERS=$(cat /tmp/initial_member_count.txt 2>/dev/null || echo "0")

# Fetch user and channel info using API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || echo "{}")

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

USER_EXISTS="false"
USER_NAME=""
USER_EMAIL=""
USER_ROLES="[]"
USER_CREATED_AT=""
IS_CHANNEL_MEMBER="false"
CHANNEL_MEMBER_COUNT="0"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  USER_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/users.info?username=maya.chen" 2>/dev/null || echo "{}")
  
  USERNAME=$(echo "$USER_INFO" | jq -r '.user.username // empty' 2>/dev/null || true)
  if [ "$USERNAME" = "maya.chen" ]; then
    USER_EXISTS="true"
    USER_NAME=$(echo "$USER_INFO" | jq -r '.user.name // empty' 2>/dev/null || true)
    USER_EMAIL=$(echo "$USER_INFO" | jq -r '.user.emails[0].address // empty' 2>/dev/null || true)
    USER_ROLES=$(echo "$USER_INFO" | jq -c '.user.roles // []' 2>/dev/null || echo "[]")
    USER_CREATED_AT=$(echo "$USER_INFO" | jq -r '.user.createdAt // empty' 2>/dev/null || true)
  fi

  # Check channel membership
  CHANNEL_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=release-updates" 2>/dev/null || echo "{}")
  CHANNEL_MEMBER_COUNT=$(echo "$CHANNEL_INFO" | jq -r '.channel.usersCount // 0' 2>/dev/null || echo "0")

  CHANNEL_MEMBERS=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.members?roomName=release-updates&count=100" 2>/dev/null || echo "{}")
  
  IS_MEMBER=$(echo "$CHANNEL_MEMBERS" | jq -r '.members[]? | select(.username == "maya.chen") | .username' 2>/dev/null || true)
  if [ "$IS_MEMBER" = "maya.chen" ]; then
    IS_CHANNEL_MEMBER="true"
  fi
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_time": $TASK_START_TIME,
  "user_exists": $USER_EXISTS,
  "user_name": "$USER_NAME",
  "user_email": "$USER_EMAIL",
  "user_roles": $USER_ROLES,
  "user_created_at": "$USER_CREATED_AT",
  "is_channel_member": $IS_CHANNEL_MEMBER,
  "initial_member_count": $INITIAL_MEMBERS,
  "final_member_count": $CHANNEL_MEMBER_COUNT
}
EOF

# Move temp file to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="