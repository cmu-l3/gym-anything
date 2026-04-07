#!/bin/bash
set -euo pipefail

echo "=== Exporting secure_rename_channel task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Task end screenshot: /tmp/task_end.png"

# Login to REST API to verify channel state
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

ROOM_TYPE=""
ROOM_NAME=""
ROOM_TOPIC=""
FOUND_ROOM="false"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Get the original channel ID from the seed manifest to prevent gaming (e.g. creating a new channel instead of renaming)
  CHANNEL_ID=$(jq -r '.workspace.channel_id // empty' "$SEED_MANIFEST_FILE" 2>/dev/null || true)
  
  if [ -n "$CHANNEL_ID" ]; then
    echo "Querying state for original channel ID: $CHANNEL_ID"
    
    # Try rooms.info first (works for both public and private in newer RC versions)
    ROOM_INFO=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/rooms.info?roomId=${CHANNEL_ID}" 2>/dev/null || true)
    
    ROOM_TYPE=$(echo "$ROOM_INFO" | jq -r '.room.t // empty' 2>/dev/null || true)
    
    if [ -n "$ROOM_TYPE" ] && [ "$ROOM_TYPE" != "null" ]; then
      FOUND_ROOM="true"
      ROOM_NAME=$(echo "$ROOM_INFO" | jq -r '.room.name // empty' 2>/dev/null || true)
      ROOM_TOPIC=$(echo "$ROOM_INFO" | jq -r '.room.topic // empty' 2>/dev/null || true)
    else
      # Fallback: Try groups.info (if it was converted to private)
      GROUP_INFO=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
        "${ROCKETCHAT_BASE_URL}/api/v1/groups.info?roomId=${CHANNEL_ID}" 2>/dev/null || true)
      ROOM_TYPE=$(echo "$GROUP_INFO" | jq -r '.group.t // empty' 2>/dev/null || true)
      
      if [ -n "$ROOM_TYPE" ] && [ "$ROOM_TYPE" != "null" ]; then
        FOUND_ROOM="true"
        ROOM_NAME=$(echo "$GROUP_INFO" | jq -r '.group.name // empty' 2>/dev/null || true)
        ROOM_TOPIC=$(echo "$GROUP_INFO" | jq -r '.group.topic // empty' 2>/dev/null || true)
      else
        # Fallback: Try channels.info (if it is still public)
        CHANNEL_INFO=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
          "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomId=${CHANNEL_ID}" 2>/dev/null || true)
        ROOM_TYPE=$(echo "$CHANNEL_INFO" | jq -r '.channel.t // empty' 2>/dev/null || true)
        
        if [ -n "$ROOM_TYPE" ] && [ "$ROOM_TYPE" != "null" ]; then
          FOUND_ROOM="true"
          ROOM_NAME=$(echo "$CHANNEL_INFO" | jq -r '.channel.name // empty' 2>/dev/null || true)
          ROOM_TOPIC=$(echo "$CHANNEL_INFO" | jq -r '.channel.topic // empty' 2>/dev/null || true)
        fi
      fi
    fi
  else
    echo "WARNING: Could not find original channel ID in seed manifest."
  fi
else
  echo "WARNING: Failed to authenticate with Rocket.Chat API."
fi

echo "Room State:"
echo "  Found: $FOUND_ROOM"
echo "  Type: $ROOM_TYPE"
echo "  Name: $ROOM_NAME"
echo "  Topic: $ROOM_TOPIC"

# Save to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "api_auth_success": $(if [ -n "$AUTH_TOKEN" ]; then echo "true"; else echo "false"; fi),
  "found_room": $FOUND_ROOM,
  "room_type": "$ROOM_TYPE",
  "room_name": "$ROOM_NAME",
  "room_topic": "$ROOM_TOPIC",
  "task_end_timestamp": $(date +%s)
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="