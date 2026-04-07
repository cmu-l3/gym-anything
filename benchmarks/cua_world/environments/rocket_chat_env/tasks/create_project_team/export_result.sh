#!/bin/bash
set -euo pipefail

echo "=== Exporting create_project_team task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Re-authenticate to query API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

# Initialize export variables
TEAM_EXISTS="false"
TEAM_ID=""
TEAM_TYPE=""
TEAM_CREATED_AT=""
MEMBER_FOUND="false"
ROOM_EXISTS="false"
ROOM_TEAM_ID=""
ROOM_TEAM_MAIN="false"
ROOM_CREATED_AT=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # 1. Query Team Info
  TEAM_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/teams.info?teamName=Q2%20Marketing" 2>/dev/null || true)
  
  if echo "$TEAM_INFO" | jq -e '.success == true' >/dev/null; then
    TEAM_EXISTS="true"
    TEAM_ID=$(echo "$TEAM_INFO" | jq -r '.team._id // empty')
    TEAM_TYPE=$(echo "$TEAM_INFO" | jq -r '.team.type // empty')
    TEAM_CREATED_AT=$(echo "$TEAM_INFO" | jq -r '.team.createdAt // empty')
    
    # 2. Query Team Members
    MEMBERS=$(curl -sS \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/teams.members?teamId=${TEAM_ID}" 2>/dev/null || true)
      
    if echo "$MEMBERS" | jq -e '.members[] | select(.user.username == "agent.user")' >/dev/null 2>&1; then
      MEMBER_FOUND="true"
    fi
  fi

  # 3. Query Room Info
  ROOM_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/rooms.info?roomName=social-media" 2>/dev/null || true)
    
  if echo "$ROOM_INFO" | jq -e '.success == true' >/dev/null; then
    ROOM_EXISTS="true"
    ROOM_TEAM_ID=$(echo "$ROOM_INFO" | jq -r '.room.teamId // empty')
    ROOM_TEAM_MAIN=$(echo "$ROOM_INFO" | jq -r '.room.teamMain // false')
    ROOM_CREATED_AT=$(echo "$ROOM_INFO" | jq -r '.room.ts // empty')
  fi
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_time": $TASK_START_TIME,
  "team_exists": $TEAM_EXISTS,
  "team_id": "$TEAM_ID",
  "team_type": "$TEAM_TYPE",
  "team_created_at": "$TEAM_CREATED_AT",
  "member_found": $MEMBER_FOUND,
  "room_exists": $ROOM_EXISTS,
  "room_team_id": "$ROOM_TEAM_ID",
  "room_team_main": $ROOM_TEAM_MAIN,
  "room_created_at": "$ROOM_CREATED_AT"
}
EOF

# Move securely to prevent permission issues
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json:"
cat /tmp/task_result.json

echo "=== Export complete ==="