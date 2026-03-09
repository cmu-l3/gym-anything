#!/bin/bash
set -euo pipefail

echo "=== Exporting vendor_security_audit_escalation result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="vendor_security_audit_escalation"
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
PENTEST_ALERT_MSG_ID=$(echo "$BASELINE" | jq -r '.pentest_alert_msg_id // empty')

# ---- Check if pentest alert message was starred ----
PENTEST_STARRED=false
if [ -n "$PENTEST_ALERT_MSG_ID" ]; then
  STAR_RESP=$(rc_api GET "chat.getStarredMessages?roomId=$(echo "$BASELINE" | jq -r '.security_alerts_id // empty')&count=100")
  if echo "$STAR_RESP" | jq -e ".messages[]? | select(._id == \"${PENTEST_ALERT_MSG_ID}\")" >/dev/null 2>&1; then
    PENTEST_STARRED=true
  fi
fi

# ---- Remediation channel ----
REM_CHANNEL_EXISTS=false
REM_CHANNEL_TYPE="none"
REM_CHANNEL_ID=""
REM_CHANNEL_TOPIC=""

GRP_RESP=$(rc_api GET "groups.info?roomName=sec-remediation-2026-03-06")
if echo "$GRP_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
  REM_CHANNEL_EXISTS=true
  REM_CHANNEL_TYPE="private"
  REM_CHANNEL_ID=$(echo "$GRP_RESP" | jq -r '.group._id // empty')
  REM_CHANNEL_TOPIC=$(echo "$GRP_RESP" | jq -r '.group.topic // empty')
fi

if [ "$REM_CHANNEL_EXISTS" = "false" ]; then
  CH_RESP=$(rc_api GET "channels.info?roomName=sec-remediation-2026-03-06")
  if echo "$CH_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
    REM_CHANNEL_EXISTS=true
    REM_CHANNEL_TYPE="public"
    REM_CHANNEL_ID=$(echo "$CH_RESP" | jq -r '.channel._id // empty')
    REM_CHANNEL_TOPIC=$(echo "$CH_RESP" | jq -r '.channel.topic // empty')
  fi
fi

# Members
echo '[]' > "$TMPDIR/members.json"
if [ -n "$REM_CHANNEL_ID" ]; then
  if [ "$REM_CHANNEL_TYPE" = "private" ]; then
    rc_api GET "groups.members?roomId=${REM_CHANNEL_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/members.json" 2>/dev/null || true
  else
    rc_api GET "channels.members?roomId=${REM_CHANNEL_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/members.json" 2>/dev/null || true
  fi
fi

# Messages and pinned
echo '[]' > "$TMPDIR/messages.json"
echo '[]' > "$TMPDIR/pinned.json"
if [ -n "$REM_CHANNEL_ID" ]; then
  if [ "$REM_CHANNEL_TYPE" = "private" ]; then
    rc_api GET "groups.history?roomId=${REM_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts, u: .u.username}] // []' > "$TMPDIR/messages.json" 2>/dev/null || true
  else
    rc_api GET "channels.history?roomId=${REM_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts, u: .u.username}] // []' > "$TMPDIR/messages.json" 2>/dev/null || true
  fi
  rc_api GET "chat.getPinnedMessages?roomId=${REM_CHANNEL_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/pinned.json" 2>/dev/null || true
fi

# Thread replies on pentest alert
echo '[]' > "$TMPDIR/threads.json"
if [ -n "$PENTEST_ALERT_MSG_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${PENTEST_ALERT_MSG_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/threads.json" 2>/dev/null || true
fi

# DMs to compliance.officer
echo '[]' > "$TMPDIR/compliance_dm.json"
DM_COMP_RESP=$(rc_api POST "im.create" '{"username":"compliance.officer"}')
DM_COMP_ROOM_ID=$(echo "$DM_COMP_RESP" | jq -r '.room._id // empty')
if [ -n "$DM_COMP_ROOM_ID" ]; then
  rc_api GET "im.history?roomId=${DM_COMP_ROOM_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/compliance_dm.json" 2>/dev/null || true
fi

# DMs to vendor.liaison
echo '[]' > "$TMPDIR/vendor_dm.json"
DM_VEND_RESP=$(rc_api POST "im.create" '{"username":"vendor.liaison"}')
DM_VEND_ROOM_ID=$(echo "$DM_VEND_RESP" | jq -r '.room._id // empty')
if [ -n "$DM_VEND_ROOM_ID" ]; then
  rc_api GET "im.history?roomId=${DM_VEND_ROOM_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/vendor_dm.json" 2>/dev/null || true
fi

# Assemble final JSON using jq (safe from quoting issues)
jq -n \
  --argjson task_start "$TASK_START" \
  --argjson rem_exists "$REM_CHANNEL_EXISTS" \
  --arg rem_type "$REM_CHANNEL_TYPE" \
  --arg rem_id "$REM_CHANNEL_ID" \
  --arg rem_topic "$REM_CHANNEL_TOPIC" \
  --slurpfile members "$TMPDIR/members.json" \
  --slurpfile messages "$TMPDIR/messages.json" \
  --slurpfile pinned "$TMPDIR/pinned.json" \
  --arg pentest_alert_id "$PENTEST_ALERT_MSG_ID" \
  --argjson pentest_starred "$PENTEST_STARRED" \
  --slurpfile threads "$TMPDIR/threads.json" \
  --slurpfile compliance_dm "$TMPDIR/compliance_dm.json" \
  --slurpfile vendor_dm "$TMPDIR/vendor_dm.json" \
  '{
    task_start: $task_start,
    remediation_channel: {
      exists: $rem_exists,
      type: $rem_type,
      id: $rem_id,
      topic: $rem_topic,
      members: $members[0],
      messages: $messages[0],
      pinned_messages: $pinned[0]
    },
    security_alerts: {
      pentest_alert_msg_id: $pentest_alert_id,
      pentest_starred: $pentest_starred,
      thread_replies: $threads[0]
    },
    compliance_officer_dm: {
      messages: $compliance_dm[0]
    },
    vendor_liaison_dm: {
      messages: $vendor_dm[0]
    }
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
