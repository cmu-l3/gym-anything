#!/bin/bash
set -euo pipefail

echo "=== Exporting incident_response_coordination result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="incident_response_coordination"
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
DB_ALERT_MSG_ID=$(echo "$BASELINE" | jq -r '.db_alert_msg_id // empty')

# ---- Incident channel ----
INC_CHANNEL_EXISTS=false
INC_CHANNEL_TYPE="none"
INC_CHANNEL_ID=""
INC_CHANNEL_TOPIC=""

GRP_RESP=$(rc_api GET "groups.info?roomName=inc-20260306-db-outage")
if echo "$GRP_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
  INC_CHANNEL_EXISTS=true
  INC_CHANNEL_TYPE="private"
  INC_CHANNEL_ID=$(echo "$GRP_RESP" | jq -r '.group._id // empty')
  INC_CHANNEL_TOPIC=$(echo "$GRP_RESP" | jq -r '.group.topic // empty')
fi

if [ "$INC_CHANNEL_EXISTS" = "false" ]; then
  CH_RESP=$(rc_api GET "channels.info?roomName=inc-20260306-db-outage")
  if echo "$CH_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
    INC_CHANNEL_EXISTS=true
    INC_CHANNEL_TYPE="public"
    INC_CHANNEL_ID=$(echo "$CH_RESP" | jq -r '.channel._id // empty')
    INC_CHANNEL_TOPIC=$(echo "$CH_RESP" | jq -r '.channel.topic // empty')
  fi
fi

# Members
echo '[]' > "$TMPDIR/members.json"
if [ -n "$INC_CHANNEL_ID" ]; then
  if [ "$INC_CHANNEL_TYPE" = "private" ]; then
    rc_api GET "groups.members?roomId=${INC_CHANNEL_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/members.json" 2>/dev/null || true
  else
    rc_api GET "channels.members?roomId=${INC_CHANNEL_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/members.json" 2>/dev/null || true
  fi
fi

# Messages and pinned
echo '[]' > "$TMPDIR/messages.json"
echo '[]' > "$TMPDIR/pinned.json"
if [ -n "$INC_CHANNEL_ID" ]; then
  if [ "$INC_CHANNEL_TYPE" = "private" ]; then
    rc_api GET "groups.history?roomId=${INC_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts, u: .u.username}] // []' > "$TMPDIR/messages.json" 2>/dev/null || true
  else
    rc_api GET "channels.history?roomId=${INC_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts, u: .u.username}] // []' > "$TMPDIR/messages.json" 2>/dev/null || true
  fi
  rc_api GET "chat.getPinnedMessages?roomId=${INC_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/pinned.json" 2>/dev/null || true
fi

# Thread replies on DB alert
echo '[]' > "$TMPDIR/threads.json"
if [ -n "$DB_ALERT_MSG_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${DB_ALERT_MSG_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/threads.json" 2>/dev/null || true
fi

# DMs to qa.engineer
echo '[]' > "$TMPDIR/qa_dm.json"
DM_RESP=$(rc_api POST "im.create" '{"username":"qa.engineer"}')
DM_ROOM_ID=$(echo "$DM_RESP" | jq -r '.room._id // empty')
if [ -n "$DM_ROOM_ID" ]; then
  rc_api GET "im.history?roomId=${DM_ROOM_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/qa_dm.json" 2>/dev/null || true
fi

# Assemble final JSON using jq (safe from quoting issues)
jq -n \
  --argjson task_start "$TASK_START" \
  --argjson inc_exists "$INC_CHANNEL_EXISTS" \
  --arg inc_type "$INC_CHANNEL_TYPE" \
  --arg inc_id "$INC_CHANNEL_ID" \
  --arg inc_topic "$INC_CHANNEL_TOPIC" \
  --slurpfile members "$TMPDIR/members.json" \
  --slurpfile messages "$TMPDIR/messages.json" \
  --slurpfile pinned "$TMPDIR/pinned.json" \
  --arg db_alert_id "$DB_ALERT_MSG_ID" \
  --slurpfile threads "$TMPDIR/threads.json" \
  --slurpfile qa_dm "$TMPDIR/qa_dm.json" \
  '{
    task_start: $task_start,
    incident_channel: {
      exists: $inc_exists,
      type: $inc_type,
      id: $inc_id,
      topic: $inc_topic,
      members: $members[0],
      messages: $messages[0],
      pinned_messages: $pinned[0]
    },
    production_alerts: {
      db_alert_msg_id: $db_alert_id,
      thread_replies: $threads[0]
    },
    qa_engineer_dm: {
      messages: $qa_dm[0]
    }
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
