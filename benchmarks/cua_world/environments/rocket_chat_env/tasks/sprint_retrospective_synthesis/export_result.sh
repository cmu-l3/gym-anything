#!/bin/bash
set -euo pipefail

echo "=== Exporting sprint_retrospective_synthesis result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="sprint_retrospective_synthesis"
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

# ---- q1-retro-action-items channel ----
ACTION_CHANNEL_EXISTS=false
ACTION_CHANNEL_TYPE="none"
ACTION_CHANNEL_ID=""
ACTION_CHANNEL_TOPIC=""

CH_RESP=$(rc_api GET "channels.info?roomName=q1-retro-action-items")
if echo "$CH_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
  ACTION_CHANNEL_EXISTS=true
  ACTION_CHANNEL_TYPE="public"
  ACTION_CHANNEL_ID=$(echo "$CH_RESP" | jq -r '.channel._id // empty')
  ACTION_CHANNEL_TOPIC=$(echo "$CH_RESP" | jq -r '.channel.topic // empty')
fi

if [ "$ACTION_CHANNEL_EXISTS" = "false" ]; then
  GRP_RESP=$(rc_api GET "groups.info?roomName=q1-retro-action-items")
  if echo "$GRP_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
    ACTION_CHANNEL_EXISTS=true
    ACTION_CHANNEL_TYPE="private"
    ACTION_CHANNEL_ID=$(echo "$GRP_RESP" | jq -r '.group._id // empty')
    ACTION_CHANNEL_TOPIC=$(echo "$GRP_RESP" | jq -r '.group.topic // empty')
  fi
fi

# Members
echo '[]' > "$TMPDIR/members.json"
if [ -n "$ACTION_CHANNEL_ID" ]; then
  if [ "$ACTION_CHANNEL_TYPE" = "private" ]; then
    rc_api GET "groups.members?roomId=${ACTION_CHANNEL_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/members.json" 2>/dev/null || true
  else
    rc_api GET "channels.members?roomId=${ACTION_CHANNEL_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/members.json" 2>/dev/null || true
  fi
fi

# Messages and pinned
echo '[]' > "$TMPDIR/messages.json"
echo '[]' > "$TMPDIR/pinned.json"
if [ -n "$ACTION_CHANNEL_ID" ]; then
  if [ "$ACTION_CHANNEL_TYPE" = "private" ]; then
    rc_api GET "groups.history?roomId=${ACTION_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts, u: .u.username}] // []' > "$TMPDIR/messages.json" 2>/dev/null || true
  else
    rc_api GET "channels.history?roomId=${ACTION_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts, u: .u.username}] // []' > "$TMPDIR/messages.json" 2>/dev/null || true
  fi
  rc_api GET "chat.getPinnedMessages?roomId=${ACTION_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/pinned.json" 2>/dev/null || true
fi

# DMs to eng.director
echo '[]' > "$TMPDIR/director_dm.json"
DM_RESP=$(rc_api POST "im.create" '{"username":"eng.director"}')
DM_ROOM_ID=$(echo "$DM_RESP" | jq -r '.room._id // empty')
if [ -n "$DM_ROOM_ID" ]; then
  rc_api GET "im.history?roomId=${DM_ROOM_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/director_dm.json" 2>/dev/null || true
fi

# Recent messages in retro channels (looking for admin's confirmation messages)
echo '[]' > "$TMPDIR/alpha_msgs.json"
echo '[]' > "$TMPDIR/beta_msgs.json"
echo '[]' > "$TMPDIR/gamma_msgs.json"

ALPHA_INFO=$(rc_api GET "channels.info?roomName=retro-team-alpha")
ALPHA_ID=$(echo "$ALPHA_INFO" | jq -r '.channel._id // empty')
if [ -n "$ALPHA_ID" ]; then
  rc_api GET "channels.history?roomId=${ALPHA_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/alpha_msgs.json" 2>/dev/null || true
fi

BETA_INFO=$(rc_api GET "channels.info?roomName=retro-team-beta")
BETA_ID=$(echo "$BETA_INFO" | jq -r '.channel._id // empty')
if [ -n "$BETA_ID" ]; then
  rc_api GET "channels.history?roomId=${BETA_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/beta_msgs.json" 2>/dev/null || true
fi

GAMMA_INFO=$(rc_api GET "channels.info?roomName=retro-team-gamma")
GAMMA_ID=$(echo "$GAMMA_INFO" | jq -r '.channel._id // empty')
if [ -n "$GAMMA_ID" ]; then
  rc_api GET "channels.history?roomId=${GAMMA_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/gamma_msgs.json" 2>/dev/null || true
fi

# Assemble final JSON using jq (safe from quoting issues)
jq -n \
  --argjson task_start "$TASK_START" \
  --argjson action_exists "$ACTION_CHANNEL_EXISTS" \
  --arg action_type "$ACTION_CHANNEL_TYPE" \
  --arg action_id "$ACTION_CHANNEL_ID" \
  --arg action_topic "$ACTION_CHANNEL_TOPIC" \
  --slurpfile members "$TMPDIR/members.json" \
  --slurpfile messages "$TMPDIR/messages.json" \
  --slurpfile pinned "$TMPDIR/pinned.json" \
  --slurpfile director_dm "$TMPDIR/director_dm.json" \
  --slurpfile alpha_msgs "$TMPDIR/alpha_msgs.json" \
  --slurpfile beta_msgs "$TMPDIR/beta_msgs.json" \
  --slurpfile gamma_msgs "$TMPDIR/gamma_msgs.json" \
  '{
    task_start: $task_start,
    action_channel: {
      exists: $action_exists,
      type: $action_type,
      id: $action_id,
      topic: $action_topic,
      members: $members[0],
      messages: $messages[0],
      pinned_messages: $pinned[0]
    },
    eng_director_dm: {
      messages: $director_dm[0]
    },
    retro_team_alpha: {
      admin_messages: $alpha_msgs[0]
    },
    retro_team_beta: {
      admin_messages: $beta_msgs[0]
    },
    retro_team_gamma: {
      admin_messages: $gamma_msgs[0]
    }
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
