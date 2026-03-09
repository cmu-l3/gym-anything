#!/bin/bash
set -euo pipefail

echo "=== Exporting cross_team_release_coordination result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="cross_team_release_coordination"
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

# ---- Coordination channel (check both public and private) ----
COORD_CHANNEL_EXISTS=false
COORD_CHANNEL_TYPE="none"
COORD_CHANNEL_ID=""
COORD_CHANNEL_TOPIC=""

CH_RESP=$(rc_api GET "channels.info?roomName=release-v3-coordination")
if echo "$CH_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
  COORD_CHANNEL_EXISTS=true
  COORD_CHANNEL_TYPE="public"
  COORD_CHANNEL_ID=$(echo "$CH_RESP" | jq -r '.channel._id // empty')
  COORD_CHANNEL_TOPIC=$(echo "$CH_RESP" | jq -r '.channel.topic // empty')
fi

if [ "$COORD_CHANNEL_EXISTS" = "false" ]; then
  GRP_RESP=$(rc_api GET "groups.info?roomName=release-v3-coordination")
  if echo "$GRP_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
    COORD_CHANNEL_EXISTS=true
    COORD_CHANNEL_TYPE="private"
    COORD_CHANNEL_ID=$(echo "$GRP_RESP" | jq -r '.group._id // empty')
    COORD_CHANNEL_TOPIC=$(echo "$GRP_RESP" | jq -r '.group.topic // empty')
  fi
fi

# Members
echo '[]' > "$TMPDIR/members.json"
if [ -n "$COORD_CHANNEL_ID" ]; then
  if [ "$COORD_CHANNEL_TYPE" = "private" ]; then
    rc_api GET "groups.members?roomId=${COORD_CHANNEL_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/members.json" 2>/dev/null || true
  else
    rc_api GET "channels.members?roomId=${COORD_CHANNEL_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/members.json" 2>/dev/null || true
  fi
fi

# Messages and pinned in coordination channel
echo '[]' > "$TMPDIR/messages.json"
echo '[]' > "$TMPDIR/pinned.json"
if [ -n "$COORD_CHANNEL_ID" ]; then
  if [ "$COORD_CHANNEL_TYPE" = "private" ]; then
    rc_api GET "groups.history?roomId=${COORD_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts, u: .u.username}] // []' > "$TMPDIR/messages.json" 2>/dev/null || true
  else
    rc_api GET "channels.history?roomId=${COORD_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts, u: .u.username}] // []' > "$TMPDIR/messages.json" 2>/dev/null || true
  fi
  rc_api GET "chat.getPinnedMessages?roomId=${COORD_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/pinned.json" 2>/dev/null || true
fi

# Recent messages in #team-frontend from admin
echo '[]' > "$TMPDIR/frontend_msgs.json"
FRONTEND_INFO=$(rc_api GET "channels.info?roomName=team-frontend")
FRONTEND_ID=$(echo "$FRONTEND_INFO" | jq -r '.channel._id // empty')
if [ -n "$FRONTEND_ID" ]; then
  rc_api GET "channels.history?roomId=${FRONTEND_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/frontend_msgs.json" 2>/dev/null || true
fi

# DMs to vp.engineering from admin
echo '[]' > "$TMPDIR/vp_dm.json"
DM_RESP=$(rc_api POST "im.create" '{"username":"vp.engineering"}')
DM_ROOM_ID=$(echo "$DM_RESP" | jq -r '.room._id // empty')
if [ -n "$DM_ROOM_ID" ]; then
  rc_api GET "im.history?roomId=${DM_ROOM_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/vp_dm.json" 2>/dev/null || true
fi

# Recent messages in #release-announcements from admin
echo '[]' > "$TMPDIR/announcements_msgs.json"
ANNOUNCE_INFO=$(rc_api GET "channels.info?roomName=release-announcements")
ANNOUNCE_ID=$(echo "$ANNOUNCE_INFO" | jq -r '.channel._id // empty')
if [ -n "$ANNOUNCE_ID" ]; then
  rc_api GET "channels.history?roomId=${ANNOUNCE_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/announcements_msgs.json" 2>/dev/null || true
fi

# Assemble final JSON using jq (safe from quoting issues)
jq -n \
  --argjson task_start "$TASK_START" \
  --argjson coord_exists "$COORD_CHANNEL_EXISTS" \
  --arg coord_type "$COORD_CHANNEL_TYPE" \
  --arg coord_id "$COORD_CHANNEL_ID" \
  --arg coord_topic "$COORD_CHANNEL_TOPIC" \
  --slurpfile members "$TMPDIR/members.json" \
  --slurpfile messages "$TMPDIR/messages.json" \
  --slurpfile pinned "$TMPDIR/pinned.json" \
  --slurpfile frontend_msgs "$TMPDIR/frontend_msgs.json" \
  --slurpfile vp_dm "$TMPDIR/vp_dm.json" \
  --slurpfile announcements_msgs "$TMPDIR/announcements_msgs.json" \
  '{
    task_start: $task_start,
    coordination_channel: {
      exists: $coord_exists,
      type: $coord_type,
      id: $coord_id,
      topic: $coord_topic,
      members: $members[0],
      messages: $messages[0],
      pinned_messages: $pinned[0]
    },
    team_frontend: {
      admin_messages: $frontend_msgs[0]
    },
    vp_engineering_dm: {
      messages: $vp_dm[0]
    },
    release_announcements: {
      admin_messages: $announcements_msgs[0]
    }
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
