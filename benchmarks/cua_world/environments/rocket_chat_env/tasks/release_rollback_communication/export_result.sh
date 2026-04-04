#!/bin/bash
set -euo pipefail

echo "=== Exporting release_rollback_communication result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="release_rollback_communication"
TASK_START=$(cat "/tmp/${TASK_NAME}_start_ts" 2>/dev/null || echo "0")
TMPDIR="/tmp/${TASK_NAME}_export"
rm -rf "$TMPDIR" && mkdir -p "$TMPDIR"

sleep 1
take_screenshot "/tmp/${TASK_NAME}_end.png"

LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)
TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken')
USERID=$(echo "$LOGIN_RESP" | jq -r '.data.userId')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo '{"error":"auth_failed"}' > "/tmp/${TASK_NAME}_result.json"
  exit 0
fi

rc_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  if [ -n "$data" ]; then
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" -d "$data" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null || echo '{}'
  else
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null || echo '{}'
  fi
}

BASELINE=$(cat "/tmp/${TASK_NAME}_baseline.json" 2>/dev/null || echo '{}')
MSG_785_ID=$(echo "$BASELINE" | jq -r '.msg_785_id // empty')
MSG_802_ID=$(echo "$BASELINE" | jq -r '.msg_802_id // empty')
RELEASE_CH_ID=$(echo "$BASELINE" | jq -r '.release_channel_id // empty')

# ---- Starred 7.8.5 ----
STARRED_785=false
if [ -n "$MSG_785_ID" ] && [ -n "$RELEASE_CH_ID" ]; then
  STARRED_RESP=$(rc_api GET "chat.getStarredMessages?roomId=${RELEASE_CH_ID}&count=50")
  if echo "$STARRED_RESP" | jq -e ".messages[] | select(._id == \"$MSG_785_ID\")" >/dev/null 2>&1; then
    STARRED_785=true
  fi
fi

# ---- Reaction on 8.0.2 ----
REACTION_802=false
REACTION_802_EMOJI=""
if [ -n "$MSG_802_ID" ]; then
  MSG_DETAIL=$(rc_api GET "chat.getMessage?msgId=${MSG_802_ID}")
  REACTIONS=$(echo "$MSG_DETAIL" | jq -r '.message.reactions // {} | keys[]' 2>/dev/null || true)
  if echo "$REACTIONS" | grep -qi "warning"; then
    REACTION_802=true
    REACTION_802_EMOJI="warning"
  elif [ -n "$REACTIONS" ]; then
    REACTION_802=true
    REACTION_802_EMOJI=$(echo "$REACTIONS" | head -1)
  fi
fi

# ---- Rollback channel ----
RB_EXISTS=false
RB_ID=""
RB_DESC=""

CH_RESP=$(rc_api GET "channels.info?roomName=rollback-8-0-2-coordination")
if echo "$CH_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
  RB_EXISTS=true
  RB_ID=$(echo "$CH_RESP" | jq -r '.channel._id // empty')
  RB_DESC=$(echo "$CH_RESP" | jq -r '.channel.description // empty')
fi
if [ "$RB_EXISTS" = "false" ]; then
  GRP_RESP=$(rc_api GET "groups.info?roomName=rollback-8-0-2-coordination")
  if echo "$GRP_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
    RB_EXISTS=true
    RB_ID=$(echo "$GRP_RESP" | jq -r '.group._id // empty')
    RB_DESC=$(echo "$GRP_RESP" | jq -r '.group.description // empty')
  fi
fi

echo '[]' > "$TMPDIR/rb_members.json"
echo '[]' > "$TMPDIR/rb_messages.json"
echo '[]' > "$TMPDIR/rb_pinned.json"
if [ -n "$RB_ID" ]; then
  rc_api GET "channels.members?roomId=${RB_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/rb_members.json" 2>/dev/null || true
  [ "$(cat "$TMPDIR/rb_members.json")" = "[]" ] && rc_api GET "groups.members?roomId=${RB_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/rb_members.json" 2>/dev/null || true

  rc_api GET "channels.history?roomId=${RB_ID}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts}] // []' > "$TMPDIR/rb_messages.json" 2>/dev/null || true
  [ "$(cat "$TMPDIR/rb_messages.json")" = "[]" ] && rc_api GET "groups.history?roomId=${RB_ID}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts}] // []' > "$TMPDIR/rb_messages.json" 2>/dev/null || true

  rc_api GET "chat.getPinnedMessages?roomId=${RB_ID}&count=50" | jq '[.messages[].msg] // []' > "$TMPDIR/rb_pinned.json" 2>/dev/null || true
fi

# ---- DM to devops.engineer ----
echo '[]' > "$TMPDIR/devops_dm.json"
DM_RESP=$(rc_api POST "im.create" '{"username":"devops.engineer"}')
DM_ROOM_ID=$(echo "$DM_RESP" | jq -r '.room._id // empty')
if [ -n "$DM_ROOM_ID" ]; then
  rc_api GET "im.history?roomId=${DM_ROOM_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/devops_dm.json" 2>/dev/null || true
fi

# ---- Release-updates announcement ----
RELEASE_ANNOUNCEMENT=""
if [ -n "$RELEASE_CH_ID" ]; then
  CH_INFO=$(rc_api GET "channels.info?roomId=${RELEASE_CH_ID}")
  RELEASE_ANNOUNCEMENT=$(echo "$CH_INFO" | jq -r '.channel.announcement // empty')
fi

# ---- Admin status ----
ADMIN_STATUS=""
ADMIN_INFO=$(rc_api GET "users.info?username=admin")
ADMIN_STATUS=$(echo "$ADMIN_INFO" | jq -r '.user.statusText // empty')

# Assemble final JSON
jq -n \
  --argjson task_start "$TASK_START" \
  --argjson starred_785 "$STARRED_785" \
  --argjson reaction_802 "$REACTION_802" \
  --arg reaction_emoji "$REACTION_802_EMOJI" \
  --argjson rb_exists "$RB_EXISTS" \
  --arg rb_id "$RB_ID" \
  --arg rb_desc "$RB_DESC" \
  --slurpfile rb_members "$TMPDIR/rb_members.json" \
  --slurpfile rb_messages "$TMPDIR/rb_messages.json" \
  --slurpfile rb_pinned "$TMPDIR/rb_pinned.json" \
  --slurpfile devops_dm "$TMPDIR/devops_dm.json" \
  --arg announcement "$RELEASE_ANNOUNCEMENT" \
  --arg admin_status "$ADMIN_STATUS" \
  '{
    task_start: $task_start,
    starred_785: $starred_785,
    reaction_802: $reaction_802,
    reaction_802_emoji: $reaction_emoji,
    rollback_channel: {
      exists: $rb_exists,
      id: $rb_id,
      description: $rb_desc,
      members: $rb_members[0],
      messages: $rb_messages[0],
      pinned_messages: $rb_pinned[0]
    },
    devops_dm: $devops_dm[0],
    release_announcement: $announcement,
    admin_status: $admin_status
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
