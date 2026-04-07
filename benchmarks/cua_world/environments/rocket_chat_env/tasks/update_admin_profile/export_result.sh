#!/bin/bash
set -euo pipefail

echo "=== Exporting update_admin_profile result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# login to API to get final state
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

FINAL_NAME=""
FINAL_STATUS=""
FINAL_AVATAR_ETAG=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  USER_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/users.info?userId=$USER_ID" 2>/dev/null)
  
  FINAL_NAME=$(echo "$USER_INFO" | jq -r '.user.name // empty')
  FINAL_STATUS=$(echo "$USER_INFO" | jq -r '.user.statusText // empty')
  FINAL_AVATAR_ETAG=$(echo "$USER_INFO" | jq -r '.user.avatarETag // empty')
else
  echo "ERROR: Could not log in to API to verify results."
fi

# Read initial state
INITIAL_AVATAR_ETAG=$(jq -r '.avatarETag // empty' /tmp/initial_user_state.json 2>/dev/null || echo "")

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "final_name": "$FINAL_NAME",
  "final_status": "$FINAL_STATUS",
  "final_avatar_etag": "$FINAL_AVATAR_ETAG",
  "initial_avatar_etag": "$INITIAL_AVATAR_ETAG",
  "screenshot_path": "/tmp/task_final.png",
  "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="