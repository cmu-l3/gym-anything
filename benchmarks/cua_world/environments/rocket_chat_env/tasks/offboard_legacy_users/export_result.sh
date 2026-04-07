#!/bin/bash
set -euo pipefail

echo "=== Exporting offboard_legacy_users task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Login to get token
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

# Default empty JSON structure if auth fails
RESULT_JSON="{\"users\":[]}"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  get_user_status() {
      local username=$1
      USER_INFO=$(curl -sS \
        -H "X-Auth-Token: $AUTH_TOKEN" \
        -H "X-User-Id: $USER_ID" \
        "${ROCKETCHAT_BASE_URL}/api/v1/users.info?username=$username" 2>/dev/null || true)
        
      local exists="false"
      local active="false"
      
      if echo "$USER_INFO" | grep -q '"success":true'; then
          exists="true"
          active=$(echo "$USER_INFO" | jq -r '.user.active // false')
      fi
      
      echo "{\"username\":\"$username\",\"exists\":$exists,\"active\":$active}"
  }

  JANE_STATUS=$(get_user_status "contractor.jane")
  MIKE_STATUS=$(get_user_status "consultant.mike")
  ADMIN_STATUS=$(get_user_status "admin")
  AGENT_STATUS=$(get_user_status "agent.user")

  RESULT_JSON=$(cat << EOF
{
  "users": [
    $JANE_STATUS,
    $MIKE_STATUS,
    $ADMIN_STATUS,
    $AGENT_STATUS
  ],
  "screenshot_path": "/tmp/task_end.png"
}
EOF
)
fi

# Write to temp file and copy
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "$RESULT_JSON" > "$TEMP_JSON"

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="