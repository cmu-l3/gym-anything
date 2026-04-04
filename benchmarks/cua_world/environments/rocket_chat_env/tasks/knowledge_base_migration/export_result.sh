#!/bin/bash
set -euo pipefail

echo "=== Exporting knowledge_base_migration result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="knowledge_base_migration"
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

export_room_state() {
  local room_name="$1"
  local prefix="$2"
  local exists=false
  local room_id=""
  local topic=""

  local ch_resp
  ch_resp=$(rc_api GET "channels.info?roomName=${room_name}")
  if echo "$ch_resp" | jq -e '.success == true' >/dev/null 2>&1; then
    exists=true
    room_id=$(echo "$ch_resp" | jq -r '.channel._id // empty')
    topic=$(echo "$ch_resp" | jq -r '.channel.topic // empty')
  fi

  if [ "$exists" = "false" ]; then
    local grp_resp
    grp_resp=$(rc_api GET "groups.info?roomName=${room_name}")
    if echo "$grp_resp" | jq -e '.success == true' >/dev/null 2>&1; then
      exists=true
      room_id=$(echo "$grp_resp" | jq -r '.group._id // empty')
      topic=$(echo "$grp_resp" | jq -r '.group.topic // empty')
    fi
  fi

  echo '[]' > "$TMPDIR/${prefix}_members.json"
  echo '[]' > "$TMPDIR/${prefix}_messages.json"
  echo '[]' > "$TMPDIR/${prefix}_pinned.json"

  if [ -n "$room_id" ]; then
    rc_api GET "channels.members?roomId=${room_id}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/${prefix}_members.json" 2>/dev/null || true
    [ "$(cat "$TMPDIR/${prefix}_members.json")" = "[]" ] && \
      rc_api GET "groups.members?roomId=${room_id}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/${prefix}_members.json" 2>/dev/null || true

    rc_api GET "channels.history?roomId=${room_id}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts}] // []' > "$TMPDIR/${prefix}_messages.json" 2>/dev/null || true
    [ "$(cat "$TMPDIR/${prefix}_messages.json")" = "[]" ] && \
      rc_api GET "groups.history?roomId=${room_id}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts}] // []' > "$TMPDIR/${prefix}_messages.json" 2>/dev/null || true

    rc_api GET "chat.getPinnedMessages?roomId=${room_id}&count=50" | jq '[.messages[].msg] // []' > "$TMPDIR/${prefix}_pinned.json" 2>/dev/null || true
  fi

  jq -n --argjson exists "$exists" --arg topic "$topic" \
    '{exists: $exists, topic: $topic}' > "$TMPDIR/${prefix}_meta.json"
}

export_room_state "kb-architecture" "arch"
export_room_state "kb-api-docs" "api"
export_room_state "kb-decisions" "dec"

# Engineering-chat messages from admin (for index message)
echo '[]' > "$TMPDIR/eng_messages.json"
ENG_CH_RESP=$(rc_api GET "channels.info?roomName=engineering-chat")
ENG_CH_ID=$(echo "$ENG_CH_RESP" | jq -r '.channel._id // empty')
if [ -n "$ENG_CH_ID" ]; then
  rc_api GET "channels.history?roomId=${ENG_CH_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/eng_messages.json" 2>/dev/null || true
fi

# DM to tech.architect
echo '[]' > "$TMPDIR/arch_dm.json"
DM_RESP=$(rc_api POST "im.create" '{"username":"tech.architect"}')
DM_ROOM_ID=$(echo "$DM_RESP" | jq -r '.room._id // empty')
if [ -n "$DM_ROOM_ID" ]; then
  rc_api GET "im.history?roomId=${DM_ROOM_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/arch_dm.json" 2>/dev/null || true
fi

# Assemble room objects
build_room() {
  local prefix="$1"
  jq -s '.[0] + {members: .[1], messages: .[2], pinned_messages: .[3]}' \
    "$TMPDIR/${prefix}_meta.json" \
    "$TMPDIR/${prefix}_members.json" \
    "$TMPDIR/${prefix}_messages.json" \
    "$TMPDIR/${prefix}_pinned.json"
}

ARCH_OBJ=$(build_room "arch")
API_OBJ=$(build_room "api")
DEC_OBJ=$(build_room "dec")

jq -n \
  --argjson task_start "$TASK_START" \
  --argjson kb_arch "$ARCH_OBJ" \
  --argjson kb_api "$API_OBJ" \
  --argjson kb_dec "$DEC_OBJ" \
  --slurpfile eng_messages "$TMPDIR/eng_messages.json" \
  --slurpfile arch_dm "$TMPDIR/arch_dm.json" \
  '{
    task_start: $task_start,
    kb_architecture: $kb_arch,
    kb_api_docs: $kb_api,
    kb_decisions: $kb_dec,
    engineering_chat_messages: $eng_messages[0],
    architect_dm: $arch_dm[0]
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
