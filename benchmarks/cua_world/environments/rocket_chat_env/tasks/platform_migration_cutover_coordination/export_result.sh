#!/bin/bash
set -euo pipefail

echo "=== Exporting platform_migration_cutover_coordination result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="platform_migration_cutover_coordination"
TASK_START=$(cat "/tmp/${TASK_NAME}_start_ts" 2>/dev/null || echo "0")
TMPDIR="/tmp/${TASK_NAME}_export"
rm -rf "$TMPDIR" && mkdir -p "$TMPDIR"

sleep 1
take_screenshot "/tmp/${TASK_NAME}_end.png"

# =========================================================================
# AUTHENTICATE
# =========================================================================
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
ALERT1_MSG_ID=$(echo "$BASELINE" | jq -r '.alert1_msg_id // empty')
ALERT2_MSG_ID=$(echo "$BASELINE" | jq -r '.alert2_msg_id // empty')
ANN_CHANNEL_ID=$(echo "$BASELINE" | jq -r '.announcements_channel_id // empty')
OPS_CHANNEL_ID=$(echo "$BASELINE" | jq -r '.ops_channel_id // empty')

# =========================================================================
# CHECK WAR ROOM CHANNEL (private group named atlas-cutover-war-room)
# =========================================================================
WAR_ROOM_EXISTS=false
WAR_ROOM_TYPE="none"
WAR_ROOM_ID=""
WAR_ROOM_TOPIC=""

# Check as private group first (task requires private)
GRP_RESP=$(rc_api GET "groups.info?roomName=atlas-cutover-war-room")
if echo "$GRP_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
  WAR_ROOM_EXISTS=true
  WAR_ROOM_TYPE="private"
  WAR_ROOM_ID=$(echo "$GRP_RESP" | jq -r '.group._id // empty')
  WAR_ROOM_TOPIC=$(echo "$GRP_RESP" | jq -r '.group.topic // empty')
fi

# Fallback: check as public channel
if [ "$WAR_ROOM_EXISTS" = "false" ]; then
  CH_RESP=$(rc_api GET "channels.info?roomName=atlas-cutover-war-room")
  if echo "$CH_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
    WAR_ROOM_EXISTS=true
    WAR_ROOM_TYPE="public"
    WAR_ROOM_ID=$(echo "$CH_RESP" | jq -r '.channel._id // empty')
    WAR_ROOM_TOPIC=$(echo "$CH_RESP" | jq -r '.channel.topic // empty')
  fi
fi

# War room members
echo '[]' > "$TMPDIR/wr_members.json"
if [ -n "$WAR_ROOM_ID" ]; then
  if [ "$WAR_ROOM_TYPE" = "private" ]; then
    rc_api GET "groups.members?roomId=${WAR_ROOM_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/wr_members.json" 2>/dev/null || true
  else
    rc_api GET "channels.members?roomId=${WAR_ROOM_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/wr_members.json" 2>/dev/null || true
  fi
fi

# War room messages
echo '[]' > "$TMPDIR/wr_messages.json"
if [ -n "$WAR_ROOM_ID" ]; then
  if [ "$WAR_ROOM_TYPE" = "private" ]; then
    rc_api GET "groups.history?roomId=${WAR_ROOM_ID}&count=100" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts, u: .u.username}] // []' > "$TMPDIR/wr_messages.json" 2>/dev/null || true
  else
    rc_api GET "channels.history?roomId=${WAR_ROOM_ID}&count=100" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts, u: .u.username}] // []' > "$TMPDIR/wr_messages.json" 2>/dev/null || true
  fi
fi

# War room pinned messages
echo '[]' > "$TMPDIR/wr_pinned.json"
if [ -n "$WAR_ROOM_ID" ]; then
  rc_api GET "chat.getPinnedMessages?roomId=${WAR_ROOM_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/wr_pinned.json" 2>/dev/null || true
fi

# =========================================================================
# THREAD REPLIES ON OPS ALERTS
# =========================================================================
echo '[]' > "$TMPDIR/alert1_threads.json"
echo '[]' > "$TMPDIR/alert2_threads.json"
if [ -n "$ALERT1_MSG_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${ALERT1_MSG_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/alert1_threads.json" 2>/dev/null || true
fi
if [ -n "$ALERT2_MSG_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${ALERT2_MSG_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/alert2_threads.json" 2>/dev/null || true
fi

# =========================================================================
# DMs TO KEY PEOPLE
# =========================================================================
dm_check() {
  local uname="$1"
  local out="$2"
  echo '[]' > "$out"
  local resp
  resp=$(rc_api POST "im.create" "{\"username\":\"${uname}\"}")
  local dm_id
  dm_id=$(echo "$resp" | jq -r '.room._id // empty')
  if [ -n "$dm_id" ]; then
    rc_api GET "im.history?roomId=${dm_id}&count=50" | \
      jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$out" 2>/dev/null || true
  fi
}

dm_check "network.lead"    "$TMPDIR/dm_network_lead.json"
dm_check "vp.engineering"  "$TMPDIR/dm_vp_engineering.json"
dm_check "db.lead"         "$TMPDIR/dm_db_lead.json"
dm_check "sre.oncall"      "$TMPDIR/dm_sre_oncall.json"

# =========================================================================
# ADMIN MESSAGES IN #engineering-announcements
# =========================================================================
echo '[]' > "$TMPDIR/ann_admin_msgs.json"
if [ -n "$ANN_CHANNEL_ID" ]; then
  rc_api GET "channels.history?roomId=${ANN_CHANNEL_ID}&count=50" | \
    jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/ann_admin_msgs.json" 2>/dev/null || true
fi

# =========================================================================
# ADMIN MESSAGES IN #ops-alerts (non-thread, for additional signal)
# =========================================================================
echo '[]' > "$TMPDIR/ops_admin_msgs.json"
if [ -n "$OPS_CHANNEL_ID" ]; then
  rc_api GET "channels.history?roomId=${OPS_CHANNEL_ID}&count=50" | \
    jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/ops_admin_msgs.json" 2>/dev/null || true
fi

# =========================================================================
# ASSEMBLE FINAL JSON
# =========================================================================
jq -n \
  --argjson task_start "$TASK_START" \
  --argjson wr_exists "$WAR_ROOM_EXISTS" \
  --arg wr_type "$WAR_ROOM_TYPE" \
  --arg wr_id "$WAR_ROOM_ID" \
  --arg wr_topic "$WAR_ROOM_TOPIC" \
  --slurpfile wr_members "$TMPDIR/wr_members.json" \
  --slurpfile wr_messages "$TMPDIR/wr_messages.json" \
  --slurpfile wr_pinned "$TMPDIR/wr_pinned.json" \
  --slurpfile alert1_threads "$TMPDIR/alert1_threads.json" \
  --slurpfile alert2_threads "$TMPDIR/alert2_threads.json" \
  --slurpfile dm_network_lead "$TMPDIR/dm_network_lead.json" \
  --slurpfile dm_vp_engineering "$TMPDIR/dm_vp_engineering.json" \
  --slurpfile dm_db_lead "$TMPDIR/dm_db_lead.json" \
  --slurpfile dm_sre_oncall "$TMPDIR/dm_sre_oncall.json" \
  --slurpfile ann_admin_msgs "$TMPDIR/ann_admin_msgs.json" \
  --slurpfile ops_admin_msgs "$TMPDIR/ops_admin_msgs.json" \
  '{
    task_start: $task_start,
    war_room: {
      exists: $wr_exists,
      type: $wr_type,
      id: $wr_id,
      topic: $wr_topic,
      members: $wr_members[0],
      messages: $wr_messages[0],
      pinned_messages: $wr_pinned[0]
    },
    alert_threads: {
      lb_502_alert: $alert1_threads[0],
      backup_failure_alert: $alert2_threads[0]
    },
    direct_messages: {
      network_lead: $dm_network_lead[0],
      vp_engineering: $dm_vp_engineering[0],
      db_lead: $dm_db_lead[0],
      sre_oncall: $dm_sre_oncall[0]
    },
    engineering_announcements: {
      admin_messages: $ann_admin_msgs[0]
    },
    ops_alerts: {
      admin_messages: $ops_admin_msgs[0]
    }
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
echo "War room found: ${WAR_ROOM_EXISTS}, type: ${WAR_ROOM_TYPE}"
