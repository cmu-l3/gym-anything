#!/bin/bash
set -euo pipefail

echo "=== Exporting client_onboarding_handoff result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="client_onboarding_handoff"
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
BRIEFING_MSG_ID=$(echo "$BASELINE" | jq -r '.briefing_msg_id // empty')

# ---- Internal channel (proj-meridian-internal) ----
INT_CHANNEL_EXISTS=false
INT_CHANNEL_TYPE="none"
INT_CHANNEL_ID=""
INT_CHANNEL_TOPIC=""

GRP_RESP=$(rc_api GET "groups.info?roomName=proj-meridian-internal")
if echo "$GRP_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
  INT_CHANNEL_EXISTS=true
  INT_CHANNEL_TYPE="private"
  INT_CHANNEL_ID=$(echo "$GRP_RESP" | jq -r '.group._id // empty')
  INT_CHANNEL_TOPIC=$(echo "$GRP_RESP" | jq -r '.group.topic // empty')
fi

if [ "$INT_CHANNEL_EXISTS" = "false" ]; then
  CH_RESP=$(rc_api GET "channels.info?roomName=proj-meridian-internal")
  if echo "$CH_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
    INT_CHANNEL_EXISTS=true
    INT_CHANNEL_TYPE="public"
    INT_CHANNEL_ID=$(echo "$CH_RESP" | jq -r '.channel._id // empty')
    INT_CHANNEL_TOPIC=$(echo "$CH_RESP" | jq -r '.channel.topic // empty')
  fi
fi

# Internal channel members
echo '[]' > "$TMPDIR/int_members.json"
if [ -n "$INT_CHANNEL_ID" ]; then
  if [ "$INT_CHANNEL_TYPE" = "private" ]; then
    rc_api GET "groups.members?roomId=${INT_CHANNEL_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/int_members.json" 2>/dev/null || true
  else
    rc_api GET "channels.members?roomId=${INT_CHANNEL_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/int_members.json" 2>/dev/null || true
  fi
fi

# Internal channel messages and pinned
echo '[]' > "$TMPDIR/int_messages.json"
echo '[]' > "$TMPDIR/int_pinned.json"
if [ -n "$INT_CHANNEL_ID" ]; then
  if [ "$INT_CHANNEL_TYPE" = "private" ]; then
    rc_api GET "groups.history?roomId=${INT_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts, u: .u.username}] // []' > "$TMPDIR/int_messages.json" 2>/dev/null || true
  else
    rc_api GET "channels.history?roomId=${INT_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts, u: .u.username}] // []' > "$TMPDIR/int_messages.json" 2>/dev/null || true
  fi
  rc_api GET "chat.getPinnedMessages?roomId=${INT_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/int_pinned.json" 2>/dev/null || true
fi

# ---- Client channel (proj-meridian-client) ----
CLI_CHANNEL_EXISTS=false
CLI_CHANNEL_TYPE="none"
CLI_CHANNEL_ID=""
CLI_CHANNEL_TOPIC=""

CH_RESP=$(rc_api GET "channels.info?roomName=proj-meridian-client")
if echo "$CH_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
  CLI_CHANNEL_EXISTS=true
  CLI_CHANNEL_TYPE="public"
  CLI_CHANNEL_ID=$(echo "$CH_RESP" | jq -r '.channel._id // empty')
  CLI_CHANNEL_TOPIC=$(echo "$CH_RESP" | jq -r '.channel.topic // empty')
fi

if [ "$CLI_CHANNEL_EXISTS" = "false" ]; then
  GRP_RESP=$(rc_api GET "groups.info?roomName=proj-meridian-client")
  if echo "$GRP_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
    CLI_CHANNEL_EXISTS=true
    CLI_CHANNEL_TYPE="private"
    CLI_CHANNEL_ID=$(echo "$GRP_RESP" | jq -r '.group._id // empty')
    CLI_CHANNEL_TOPIC=$(echo "$GRP_RESP" | jq -r '.group.topic // empty')
  fi
fi

# Client channel members
echo '[]' > "$TMPDIR/cli_members.json"
if [ -n "$CLI_CHANNEL_ID" ]; then
  if [ "$CLI_CHANNEL_TYPE" = "public" ]; then
    rc_api GET "channels.members?roomId=${CLI_CHANNEL_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/cli_members.json" 2>/dev/null || true
  else
    rc_api GET "groups.members?roomId=${CLI_CHANNEL_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/cli_members.json" 2>/dev/null || true
  fi
fi

# Client channel messages
echo '[]' > "$TMPDIR/cli_messages.json"
if [ -n "$CLI_CHANNEL_ID" ]; then
  if [ "$CLI_CHANNEL_TYPE" = "public" ]; then
    rc_api GET "channels.history?roomId=${CLI_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/cli_messages.json" 2>/dev/null || true
  else
    rc_api GET "groups.history?roomId=${CLI_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/cli_messages.json" 2>/dev/null || true
  fi
fi

# Thread replies on briefing message
echo '[]' > "$TMPDIR/threads.json"
if [ -n "$BRIEFING_MSG_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${BRIEFING_MSG_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/threads.json" 2>/dev/null || true
fi

# DMs to solutions.architect
echo '[]' > "$TMPDIR/sa_dm.json"
DM_RESP=$(rc_api POST "im.create" '{"username":"solutions.architect"}')
DM_ROOM_ID=$(echo "$DM_RESP" | jq -r '.room._id // empty')
if [ -n "$DM_ROOM_ID" ]; then
  rc_api GET "im.history?roomId=${DM_ROOM_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/sa_dm.json" 2>/dev/null || true
fi

# Assemble final JSON using jq (safe from quoting issues)
jq -n \
  --argjson task_start "$TASK_START" \
  --argjson int_exists "$INT_CHANNEL_EXISTS" \
  --arg int_type "$INT_CHANNEL_TYPE" \
  --arg int_id "$INT_CHANNEL_ID" \
  --arg int_topic "$INT_CHANNEL_TOPIC" \
  --slurpfile int_members "$TMPDIR/int_members.json" \
  --slurpfile int_messages "$TMPDIR/int_messages.json" \
  --slurpfile int_pinned "$TMPDIR/int_pinned.json" \
  --argjson cli_exists "$CLI_CHANNEL_EXISTS" \
  --arg cli_type "$CLI_CHANNEL_TYPE" \
  --arg cli_id "$CLI_CHANNEL_ID" \
  --arg cli_topic "$CLI_CHANNEL_TOPIC" \
  --slurpfile cli_members "$TMPDIR/cli_members.json" \
  --slurpfile cli_messages "$TMPDIR/cli_messages.json" \
  --arg briefing_id "$BRIEFING_MSG_ID" \
  --slurpfile threads "$TMPDIR/threads.json" \
  --slurpfile sa_dm "$TMPDIR/sa_dm.json" \
  '{
    task_start: $task_start,
    internal_channel: {
      exists: $int_exists,
      type: $int_type,
      id: $int_id,
      topic: $int_topic,
      members: $int_members[0],
      messages: $int_messages[0],
      pinned_messages: $int_pinned[0]
    },
    client_channel: {
      exists: $cli_exists,
      type: $cli_type,
      id: $cli_id,
      topic: $cli_topic,
      members: $cli_members[0],
      messages: $cli_messages[0]
    },
    sales_handoffs: {
      briefing_msg_id: $briefing_id,
      thread_replies: $threads[0]
    },
    solutions_architect_dm: {
      messages: $sa_dm[0]
    }
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
