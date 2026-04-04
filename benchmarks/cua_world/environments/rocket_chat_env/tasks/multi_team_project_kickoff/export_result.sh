#!/bin/bash
set -euo pipefail

echo "=== Exporting multi_team_project_kickoff result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="multi_team_project_kickoff"
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

# Helper to export room state to temp files
export_room_state() {
  local room_name="$1"
  local prefix="$2"
  local exists=false
  local room_type="none"
  local room_id=""
  local topic=""
  local description=""

  # Try public channel
  local ch_resp
  ch_resp=$(rc_api GET "channels.info?roomName=${room_name}")
  if echo "$ch_resp" | jq -e '.success == true' >/dev/null 2>&1; then
    exists=true
    room_type="public"
    room_id=$(echo "$ch_resp" | jq -r '.channel._id // empty')
    topic=$(echo "$ch_resp" | jq -r '.channel.topic // empty')
    description=$(echo "$ch_resp" | jq -r '.channel.description // empty')
  fi

  # Try private group
  if [ "$exists" = "false" ]; then
    local grp_resp
    grp_resp=$(rc_api GET "groups.info?roomName=${room_name}")
    if echo "$grp_resp" | jq -e '.success == true' >/dev/null 2>&1; then
      exists=true
      room_type="private"
      room_id=$(echo "$grp_resp" | jq -r '.group._id // empty')
      topic=$(echo "$grp_resp" | jq -r '.group.topic // empty')
      description=$(echo "$grp_resp" | jq -r '.group.description // empty')
    fi
  fi

  echo '[]' > "$TMPDIR/${prefix}_members.json"
  echo '[]' > "$TMPDIR/${prefix}_messages.json"
  echo '[]' > "$TMPDIR/${prefix}_pinned.json"

  if [ -n "$room_id" ]; then
    if [ "$room_type" = "private" ]; then
      rc_api GET "groups.members?roomId=${room_id}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/${prefix}_members.json" 2>/dev/null || true
      rc_api GET "groups.history?roomId=${room_id}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts}] // []' > "$TMPDIR/${prefix}_messages.json" 2>/dev/null || true
    else
      rc_api GET "channels.members?roomId=${room_id}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/${prefix}_members.json" 2>/dev/null || true
      rc_api GET "channels.history?roomId=${room_id}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts}] // []' > "$TMPDIR/${prefix}_messages.json" 2>/dev/null || true
    fi
    rc_api GET "chat.getPinnedMessages?roomId=${room_id}&count=50" | jq '[.messages[].msg] // []' > "$TMPDIR/${prefix}_pinned.json" 2>/dev/null || true
  fi

  # Write metadata
  jq -n --argjson exists "$exists" --arg type "$room_type" --arg topic "$topic" --arg description "$description" \
    '{exists: $exists, type: $type, topic: $topic, description: $description}' > "$TMPDIR/${prefix}_meta.json"
}

export_room_state "phoenix-migration" "main"
export_room_state "phoenix-frontend" "fe"
export_room_state "phoenix-backend" "be"
export_room_state "phoenix-devops" "devops"

# DM to pm.coordinator
echo '[]' > "$TMPDIR/pm_dm.json"
DM_RESP=$(rc_api POST "im.create" '{"username":"pm.coordinator"}')
DM_ROOM_ID=$(echo "$DM_RESP" | jq -r '.room._id // empty')
if [ -n "$DM_ROOM_ID" ]; then
  rc_api GET "im.history?roomId=${DM_ROOM_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/pm_dm.json" 2>/dev/null || true
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

MAIN_OBJ=$(build_room "main")
FE_OBJ=$(build_room "fe")
BE_OBJ=$(build_room "be")
DEVOPS_OBJ=$(build_room "devops")

jq -n \
  --argjson task_start "$TASK_START" \
  --argjson main "$MAIN_OBJ" \
  --argjson fe "$FE_OBJ" \
  --argjson be "$BE_OBJ" \
  --argjson devops "$DEVOPS_OBJ" \
  --slurpfile pm_dm "$TMPDIR/pm_dm.json" \
  '{
    task_start: $task_start,
    main_channel: $main,
    frontend_channel: $fe,
    backend_channel: $be,
    devops_channel: $devops,
    pm_dm: $pm_dm[0]
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
