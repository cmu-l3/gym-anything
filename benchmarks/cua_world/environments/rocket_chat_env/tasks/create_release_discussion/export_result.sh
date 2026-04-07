#!/bin/bash
set -euo pipefail

echo "=== Exporting create_release_discussion result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final visual state
take_screenshot /tmp/task_final.png
echo "Final screenshot captured."

# 2. Gather Data via API
# We need to find the discussion room and check its properties
echo "Querying API for discussion status..."

LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || echo '{}')

RC_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
RC_USERID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PARENT_CHANNEL_ID=$(cat /tmp/parent_channel_id.txt 2>/dev/null || echo "")

DISCUSSION_FOUND="false"
DISCUSSION_ID=""
DISCUSSION_NAME=""
DISCUSSION_TS=""
PARENT_ID=""
INITIAL_MSG_TEXT=""

if [ -n "$RC_TOKEN" ] && [ -n "$RC_USERID" ]; then
  # Search for the room by name filter
  ROOMS_RESP=$(curl -sS -X GET \
    -H "X-Auth-Token: $RC_TOKEN" \
    -H "X-User-Id: $RC_USERID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/rooms.adminRooms?filter=Upgrade%20Planning&count=10" 2>/dev/null)
  
  # Filter strictly for the name "Upgrade Planning Discussion"
  # Note: discussion rooms often store the name in `fname` or `name`
  TARGET_ROOM=$(echo "$ROOMS_RESP" | jq -r '.rooms[]? | select(.fname == "Upgrade Planning Discussion" or .name == "Upgrade Planning Discussion")' | head -n 1)
  
  if [ -n "$TARGET_ROOM" ] && [ "$TARGET_ROOM" != "null" ]; then
    DISCUSSION_FOUND="true"
    DISCUSSION_ID=$(echo "$TARGET_ROOM" | jq -r '._id')
    DISCUSSION_NAME=$(echo "$TARGET_ROOM" | jq -r '.fname // .name')
    DISCUSSION_TS=$(echo "$TARGET_ROOM" | jq -r '.ts')
    PARENT_ID=$(echo "$TARGET_ROOM" | jq -r '.prid // empty')
    
    # Get history to find the initial message
    # Discussions are technically "groups" or "channels" depending on version, usually groups (private)
    HISTORY_RESP=$(curl -sS -X GET \
      -H "X-Auth-Token: $RC_TOKEN" \
      -H "X-User-Id: $RC_USERID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/groups.history?roomId=${DISCUSSION_ID}&count=5" 2>/dev/null)
    
    # Look for the message text
    INITIAL_MSG_TEXT=$(echo "$HISTORY_RESP" | jq -r '.messages[]? | select(.msg | contains("Team, let")) | .msg' | head -n 1)
  fi
fi

# 3. Create JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_time": $TASK_START_TIME,
  "discussion_found": $DISCUSSION_FOUND,
  "discussion_id": "$DISCUSSION_ID",
  "discussion_name": "$DISCUSSION_NAME",
  "discussion_ts": "$DISCUSSION_TS",
  "actual_parent_id": "$PARENT_ID",
  "expected_parent_id": "$PARENT_CHANNEL_ID",
  "initial_message_text": $(echo "$INITIAL_MSG_TEXT" | jq -R .),
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="