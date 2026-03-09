#!/bin/bash
set -euo pipefail

echo "=== Exporting hospital_it_ransomware_response result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="hospital_it_ransomware_response"
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
BASELINE_GROUPS=$(echo "$BASELINE" | jq '.baseline_groups // []')
CLINICAL_CRITICAL_MSG_ID=$(echo "$BASELINE" | jq -r '.clinical_critical_msg_id // empty')
NURSING_URGENT_MSG_ID=$(echo "$BASELINE" | jq -r '.nursing_urgent_msg_id // empty')
ITSEC_CONFIRMED_MSG_ID=$(echo "$BASELINE" | jq -r '.itsec_confirmed_msg_id // empty')

# ---- Find new private channels created by the agent ----
ALL_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[] | {name: .name, id: ._id, topic: (.topic // ""), fname: (.fname // "")}]' 2>/dev/null || echo '[]')

# Identify new groups (those NOT in baseline)
echo "$ALL_GROUPS" > "$TMPDIR/all_groups.json"
echo "$BASELINE_GROUPS" > "$TMPDIR/baseline_groups.json"

# Use Python to find new groups and identify the incident channel
python3 << 'PYEOF'
import json, os

tmpdir = os.environ.get('TMPDIR', '/tmp/hospital_it_ransomware_response_export')
all_groups = json.load(open(f'{tmpdir}/all_groups.json'))
baseline_groups = json.load(open(f'{tmpdir}/baseline_groups.json'))
baseline_set = set(baseline_groups)

new_groups = [g for g in all_groups if g['name'] not in baseline_set]

# Score each new group for being an incident channel
incident_keywords = ['inc', 'incident', 'ransomware', 'ir-', 'emergency', 'crisis', 'response', 'ehr', 'breach', 'security', 'lockbit', 'cyber']

best_group = None
best_score = -1
for g in new_groups:
    name_lower = g['name'].lower()
    topic_lower = (g.get('topic') or '').lower()
    score = sum(1 for kw in incident_keywords if kw in name_lower or kw in topic_lower)
    if score > best_score:
        best_score = score
        best_group = g

result = {
    'new_groups': new_groups,
    'incident_channel': best_group or {},
    'incident_channel_found': best_group is not None
}

with open(f'{tmpdir}/incident_channel.json', 'w') as f:
    json.dump(result, f)
PYEOF

INCIDENT_DATA=$(cat "$TMPDIR/incident_channel.json" 2>/dev/null || echo '{"new_groups":[],"incident_channel":{},"incident_channel_found":false}')
INC_ID=$(echo "$INCIDENT_DATA" | jq -r '.incident_channel.id // empty')
INC_NAME=$(echo "$INCIDENT_DATA" | jq -r '.incident_channel.name // empty')
INC_TOPIC=$(echo "$INCIDENT_DATA" | jq -r '.incident_channel.topic // empty')
INC_FOUND=$(echo "$INCIDENT_DATA" | jq -r '.incident_channel_found')

# Members
echo '[]' > "$TMPDIR/inc_members.json"
if [ -n "$INC_ID" ]; then
  rc_api GET "groups.members?roomId=${INC_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/inc_members.json" 2>/dev/null || true
fi

# Messages and pinned
echo '[]' > "$TMPDIR/inc_messages.json"
echo '[]' > "$TMPDIR/inc_pinned.json"
if [ -n "$INC_ID" ]; then
  rc_api GET "groups.history?roomId=${INC_ID}&count=100" | jq '[.messages[] | {msg: .msg, pinned: (.pinned // false), ts: .ts, u: (.u.username // "system"), tmid: (.tmid // "")}] // []' > "$TMPDIR/inc_messages.json" 2>/dev/null || true
  rc_api GET "chat.getPinnedMessages?roomId=${INC_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/inc_pinned.json" 2>/dev/null || true
fi

# Thread replies on seeded alert messages
echo '[]' > "$TMPDIR/clinical_threads.json"
echo '[]' > "$TMPDIR/nursing_threads.json"
echo '[]' > "$TMPDIR/itsec_threads.json"

if [ -n "$CLINICAL_CRITICAL_MSG_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${CLINICAL_CRITICAL_MSG_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/clinical_threads.json" 2>/dev/null || true
fi
if [ -n "$NURSING_URGENT_MSG_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${NURSING_URGENT_MSG_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/nursing_threads.json" 2>/dev/null || true
fi
if [ -n "$ITSEC_CONFIRMED_MSG_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${ITSEC_CONFIRMED_MSG_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/itsec_threads.json" 2>/dev/null || true
fi

# DMs to clinical.coordinator
echo '[]' > "$TMPDIR/clinical_dm.json"
DM_CLIN_RESP=$(rc_api POST "im.create" '{"username":"clinical.coordinator"}')
DM_CLIN_ID=$(echo "$DM_CLIN_RESP" | jq -r '.room._id // empty')
if [ -n "$DM_CLIN_ID" ]; then
  rc_api GET "im.history?roomId=${DM_CLIN_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/clinical_dm.json" 2>/dev/null || true
fi

# DMs to it.security
echo '[]' > "$TMPDIR/itsec_dm.json"
DM_SEC_RESP=$(rc_api POST "im.create" '{"username":"it.security"}')
DM_SEC_ID=$(echo "$DM_SEC_RESP" | jq -r '.room._id // empty')
if [ -n "$DM_SEC_ID" ]; then
  rc_api GET "im.history?roomId=${DM_SEC_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/itsec_dm.json" 2>/dev/null || true
fi

# DMs to ciso
echo '[]' > "$TMPDIR/ciso_dm.json"
DM_CISO_RESP=$(rc_api POST "im.create" '{"username":"ciso"}')
DM_CISO_ID=$(echo "$DM_CISO_RESP" | jq -r '.room._id // empty')
if [ -n "$DM_CISO_ID" ]; then
  rc_api GET "im.history?roomId=${DM_CISO_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/ciso_dm.json" 2>/dev/null || true
fi

# Assemble final result
jq -n \
  --argjson task_start "$TASK_START" \
  --argjson inc_found "$INC_FOUND" \
  --arg inc_name "$INC_NAME" \
  --arg inc_id "$INC_ID" \
  --arg inc_topic "$INC_TOPIC" \
  --slurpfile inc_members "$TMPDIR/inc_members.json" \
  --slurpfile inc_messages "$TMPDIR/inc_messages.json" \
  --slurpfile inc_pinned "$TMPDIR/inc_pinned.json" \
  --arg clinical_critical_msg_id "$CLINICAL_CRITICAL_MSG_ID" \
  --arg nursing_urgent_msg_id "$NURSING_URGENT_MSG_ID" \
  --arg itsec_confirmed_msg_id "$ITSEC_CONFIRMED_MSG_ID" \
  --slurpfile clinical_threads "$TMPDIR/clinical_threads.json" \
  --slurpfile nursing_threads "$TMPDIR/nursing_threads.json" \
  --slurpfile itsec_threads "$TMPDIR/itsec_threads.json" \
  --slurpfile clinical_dm "$TMPDIR/clinical_dm.json" \
  --slurpfile itsec_dm "$TMPDIR/itsec_dm.json" \
  --slurpfile ciso_dm "$TMPDIR/ciso_dm.json" \
  '{
    task_start: $task_start,
    incident_channel: {
      found: $inc_found,
      name: $inc_name,
      id: $inc_id,
      topic: $inc_topic,
      members: $inc_members[0],
      messages: $inc_messages[0],
      pinned_messages: $inc_pinned[0]
    },
    alert_thread_replies: {
      clinical_it_alerts: $clinical_threads[0],
      nursing_coordination: $nursing_threads[0],
      it_security_ops: $itsec_threads[0]
    },
    direct_messages: {
      clinical_coordinator: $clinical_dm[0],
      it_security: $itsec_dm[0],
      ciso: $ciso_dm[0]
    }
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
echo "Incident channel found: ${INC_FOUND}, name: ${INC_NAME:-none}"
