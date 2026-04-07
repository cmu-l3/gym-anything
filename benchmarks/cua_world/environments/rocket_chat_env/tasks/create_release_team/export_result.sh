#!/bin/bash
set -euo pipefail

echo "=== Exporting create_release_team task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
TEAM_EXISTS="false"
TEAM_ID=""
TEAM_TYPE="-1"
TEAM_NAME=""
ROOM_ID=""
DESCRIPTION=""
CREATED_AT=""
AGENT_IS_MEMBER="false"
CHANNEL_IN_TEAM="false"

# Authenticate to query API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
AUTH_USERID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$AUTH_USERID" ]; then
  echo "Authenticated. Querying team info..."
  
  # 1. Get Team Info
  TEAM_INFO_RESP=$(curl -sS -X GET \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $AUTH_USERID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/teams.info?teamName=release-management" 2>/dev/null || true)
  
  TEAM_ID=$(echo "$TEAM_INFO_RESP" | jq -r '.teamInfo._id // empty')
  
  if [ -n "$TEAM_ID" ]; then
    TEAM_EXISTS="true"
    TEAM_TYPE=$(echo "$TEAM_INFO_RESP" | jq -r '.teamInfo.type // -1')
    TEAM_NAME=$(echo "$TEAM_INFO_RESP" | jq -r '.teamInfo.name // empty')
    ROOM_ID=$(echo "$TEAM_INFO_RESP" | jq -r '.teamInfo.roomId // empty')
    CREATED_AT_ISO=$(echo "$TEAM_INFO_RESP" | jq -r '.teamInfo.createdAt // empty')
    # Convert ISO date to timestamp if possible, otherwise keep string
    CREATED_AT="$CREATED_AT_ISO"
    
    # 2. Get Room Info (for description)
    if [ -n "$ROOM_ID" ]; then
        ROOM_INFO_RESP=$(curl -sS -X GET \
          -H "X-Auth-Token: $AUTH_TOKEN" \
          -H "X-User-Id: $AUTH_USERID" \
          "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomId=${ROOM_ID}" 2>/dev/null || true)
        DESCRIPTION=$(echo "$ROOM_INFO_RESP" | jq -r '.channel.description // empty')
    fi
    
    # 3. Check Members (agent.user)
    MEMBERS_RESP=$(curl -sS -X GET \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $AUTH_USERID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/teams.members?teamId=${TEAM_ID}" 2>/dev/null || true)
      
    # Check if agent.user is in the member list
    if echo "$MEMBERS_RESP" | grep -q "\"username\":\"agent.user\""; then
        AGENT_IS_MEMBER="true"
    fi
    
    # 4. Check Team Rooms (release-updates)
    ROOMS_RESP=$(curl -sS -X GET \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $AUTH_USERID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/teams.listRooms?teamId=${TEAM_ID}" 2>/dev/null || true)
      
    # Check if release-updates is in the room list
    if echo "$ROOMS_RESP" | grep -q "\"name\":\"release-updates\""; then
        CHANNEL_IN_TEAM="true"
    fi
  fi
else
  echo "ERROR: Failed to authenticate for verification."
fi

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START,
    "task_end_ts": $TASK_END,
    "team_exists": $TEAM_EXISTS,
    "team_id": "$TEAM_ID",
    "team_type": $TEAM_TYPE,
    "team_name": "$TEAM_NAME",
    "description": "$(echo "$DESCRIPTION" | sed 's/"/\\"/g')",
    "created_at": "$CREATED_AT",
    "agent_is_member": $AGENT_IS_MEMBER,
    "channel_in_team": $CHANNEL_IN_TEAM,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="