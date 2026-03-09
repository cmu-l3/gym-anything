#!/bin/bash
set -euo pipefail

echo "=== Exporting oss_cve_disclosure_coordination result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="oss_cve_disclosure_coordination"
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
TRIAGE_MSG1_ID=$(echo "$BASELINE" | jq -r '.triage_msg1_id // empty')
TRIAGE_MSG2_ID=$(echo "$BASELINE" | jq -r '.triage_msg2_id // empty')

# Find new private channels (coordination channels created by agent)
ALL_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[] | {name: .name, id: ._id, topic: (.topic // ""), fname: (.fname // "")}]' 2>/dev/null || echo '[]')

echo "$ALL_GROUPS" > "$TMPDIR/all_groups.json"
echo "$BASELINE_GROUPS" > "$TMPDIR/baseline_groups.json"

python3 << 'PYEOF'
import json, os

tmpdir = os.environ.get('TMPDIR', '/tmp/oss_cve_disclosure_coordination_export')
all_groups = json.load(open(f'{tmpdir}/all_groups.json'))
baseline_groups = json.load(open(f'{tmpdir}/baseline_groups.json'))
baseline_set = set(baseline_groups)

new_groups = [g for g in all_groups if g['name'] not in baseline_set]

# Score for primary coordination channel (private embargo channel)
embargo_kw = ['cve', 'embargo', 'disclosure', 'coord', 'vuln', 'security', 'patch', 'advisory', 'private']

best_group = None
best_score = -1
for g in new_groups:
    name_lower = g['name'].lower()
    topic_lower = (g.get('topic') or '').lower()
    s = sum(1 for kw in embargo_kw if kw in name_lower or kw in topic_lower)
    if s > best_score:
        best_score = s
        best_group = g

result = {
    'new_groups': new_groups,
    'coord_channel': best_group or {},
    'coord_channel_found': best_group is not None
}

with open(f'{tmpdir}/coord_channel.json', 'w') as f:
    json.dump(result, f)
PYEOF

COORD_DATA=$(cat "$TMPDIR/coord_channel.json" 2>/dev/null || echo '{"new_groups":[],"coord_channel":{},"coord_channel_found":false}')
CC_ID=$(echo "$COORD_DATA" | jq -r '.coord_channel.id // empty')
CC_NAME=$(echo "$COORD_DATA" | jq -r '.coord_channel.name // empty')
CC_FOUND=$(echo "$COORD_DATA" | jq '.coord_channel_found')
NEW_GROUP_COUNT=$(echo "$COORD_DATA" | jq '.new_groups | length')

echo '[]' > "$TMPDIR/cc_messages.json"
echo '[]' > "$TMPDIR/cc_members.json"
if [ -n "$CC_ID" ]; then
  rc_api GET "groups.history?roomId=${CC_ID}&count=200" | jq '[.messages[] | {msg: .msg, ts: .ts, u: (.u.username // "system")}] // []' > "$TMPDIR/cc_messages.json" 2>/dev/null || true
  rc_api GET "groups.members?roomId=${CC_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/cc_members.json" 2>/dev/null || true
fi

# Thread replies on triage messages
echo '[]' > "$TMPDIR/triage1_threads.json"
echo '[]' > "$TMPDIR/triage2_threads.json"
if [ -n "$TRIAGE_MSG1_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${TRIAGE_MSG1_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/triage1_threads.json" 2>/dev/null || true
fi
if [ -n "$TRIAGE_MSG2_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${TRIAGE_MSG2_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/triage2_threads.json" 2>/dev/null || true
fi

# DMs to all relevant parties
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

dm_check "security.researcher" "$TMPDIR/dm_researcher.json"
dm_check "core.maintainer" "$TMPDIR/dm_core_maintainer.json"
dm_check "release.manager" "$TMPDIR/dm_release_manager.json"
dm_check "enterprise.consumer" "$TMPDIR/dm_enterprise.json"
dm_check "cloud.vendor" "$TMPDIR/dm_cloud_vendor.json"
dm_check "distro.maintainer" "$TMPDIR/dm_distro.json"
dm_check "foundation.counsel" "$TMPDIR/dm_counsel.json"

# Triage channel messages from admin
TRIAGE_ID=$(echo "$BASELINE" | jq -r '.triage_channel_id // empty')
echo '[]' > "$TMPDIR/triage_admin_msgs.json"
if [ -n "$TRIAGE_ID" ]; then
  rc_api GET "channels.history?roomId=${TRIAGE_ID}&count=200" | \
    jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/triage_admin_msgs.json" 2>/dev/null || true
fi

jq -n \
  --argjson task_start "$TASK_START" \
  --argjson cc_found "$CC_FOUND" \
  --arg cc_name "$CC_NAME" \
  --arg cc_id "$CC_ID" \
  --argjson new_group_count "$NEW_GROUP_COUNT" \
  --slurpfile cc_messages "$TMPDIR/cc_messages.json" \
  --slurpfile cc_members "$TMPDIR/cc_members.json" \
  --slurpfile triage1_threads "$TMPDIR/triage1_threads.json" \
  --slurpfile triage2_threads "$TMPDIR/triage2_threads.json" \
  --slurpfile dm_researcher "$TMPDIR/dm_researcher.json" \
  --slurpfile dm_core_maintainer "$TMPDIR/dm_core_maintainer.json" \
  --slurpfile dm_release_manager "$TMPDIR/dm_release_manager.json" \
  --slurpfile dm_enterprise "$TMPDIR/dm_enterprise.json" \
  --slurpfile dm_cloud_vendor "$TMPDIR/dm_cloud_vendor.json" \
  --slurpfile dm_distro "$TMPDIR/dm_distro.json" \
  --slurpfile dm_counsel "$TMPDIR/dm_counsel.json" \
  --slurpfile triage_admin_msgs "$TMPDIR/triage_admin_msgs.json" \
  '{
    task_start: $task_start,
    coord_channel: {
      found: $cc_found,
      name: $cc_name,
      id: $cc_id,
      messages: $cc_messages[0],
      members: $cc_members[0]
    },
    new_group_count: $new_group_count,
    triage_threads: {
      triage_assessment: $triage1_threads[0],
      triage_timeline: $triage2_threads[0]
    },
    direct_messages: {
      researcher: $dm_researcher[0],
      core_maintainer: $dm_core_maintainer[0],
      release_manager: $dm_release_manager[0],
      enterprise_consumer: $dm_enterprise[0],
      cloud_vendor: $dm_cloud_vendor[0],
      distro_maintainer: $dm_distro[0],
      foundation_counsel: $dm_counsel[0]
    },
    triage_admin_messages: $triage_admin_msgs[0]
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
echo "Coordination channel: ${CC_FOUND}, name: ${CC_NAME:-none}"
