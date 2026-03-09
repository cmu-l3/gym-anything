#!/bin/bash
set -euo pipefail

echo "=== Exporting multi_team_release_blockers result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="multi_team_release_blockers"
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
RV4_MSG1_ID=$(echo "$BASELINE" | jq -r '.rv4_msg1_id // empty')
RV4_MSG2_ID=$(echo "$BASELINE" | jq -r '.rv4_msg2_id // empty')
RV4_MSG3_ID=$(echo "$BASELINE" | jq -r '.rv4_msg3_id // empty')

# Find new private groups (go/no-go channel, blocker coordination channel)
ALL_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[] | {name: .name, id: ._id, topic: (.topic // "")}]' 2>/dev/null || echo '[]')
echo "$ALL_GROUPS" > "$TMPDIR/all_groups.json"
echo "$BASELINE_GROUPS" > "$TMPDIR/baseline_groups.json"

python3 << 'PYEOF'
import json, os

tmpdir = os.environ.get('TMPDIR', '/tmp/multi_team_release_blockers_export')
all_groups = json.load(open(f'{tmpdir}/all_groups.json'))
baseline_groups = json.load(open(f'{tmpdir}/baseline_groups.json'))
baseline_set = set(baseline_groups)

new_groups = [g for g in all_groups if g['name'] not in baseline_set]

# Score for release coordination/go-no-go channel
coord_kw = ['release', 'v4', 'blocker', 'go-no-go', 'gonogo', 'decision', 'coord', 'unblock', 'ship']

best_group = None
best_score = -1
for g in new_groups:
    name_lower = g['name'].lower()
    topic_lower = (g.get('topic') or '').lower()
    s = sum(1 for kw in coord_kw if kw in name_lower or kw in topic_lower)
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

# Thread replies on each blocker message
echo '[]' > "$TMPDIR/msg1_threads.json"
echo '[]' > "$TMPDIR/msg2_threads.json"
echo '[]' > "$TMPDIR/msg3_threads.json"
if [ -n "$RV4_MSG1_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${RV4_MSG1_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/msg1_threads.json" 2>/dev/null || true
fi
if [ -n "$RV4_MSG2_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${RV4_MSG2_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/msg2_threads.json" 2>/dev/null || true
fi
if [ -n "$RV4_MSG3_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${RV4_MSG3_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/msg3_threads.json" 2>/dev/null || true
fi

# DMs to all key stakeholders
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

dm_check "backend.lead" "$TMPDIR/dm_backend.json"
dm_check "security.eng" "$TMPDIR/dm_security.json"
dm_check "qa.lead" "$TMPDIR/dm_qa.json"
dm_check "vp.engineering" "$TMPDIR/dm_vp.json"
dm_check "product.manager" "$TMPDIR/dm_product.json"
dm_check "sales.lead" "$TMPDIR/dm_sales.json"
dm_check "devops.lead" "$TMPDIR/dm_devops.json"

# Admin messages in release-v4 channel
RV4_CHANNEL_ID=$(echo "$BASELINE" | jq -r '.rv4_channel_id // empty')
echo '[]' > "$TMPDIR/rv4_admin_msgs.json"
if [ -n "$RV4_CHANNEL_ID" ]; then
  rc_api GET "channels.history?roomId=${RV4_CHANNEL_ID}&count=200" | \
    jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/rv4_admin_msgs.json" 2>/dev/null || true
fi

jq -n \
  --argjson task_start "$TASK_START" \
  --argjson cc_found "$CC_FOUND" \
  --arg cc_name "$CC_NAME" \
  --arg cc_id "$CC_ID" \
  --argjson new_group_count "$NEW_GROUP_COUNT" \
  --slurpfile cc_messages "$TMPDIR/cc_messages.json" \
  --slurpfile cc_members "$TMPDIR/cc_members.json" \
  --slurpfile msg1_threads "$TMPDIR/msg1_threads.json" \
  --slurpfile msg2_threads "$TMPDIR/msg2_threads.json" \
  --slurpfile msg3_threads "$TMPDIR/msg3_threads.json" \
  --slurpfile dm_backend "$TMPDIR/dm_backend.json" \
  --slurpfile dm_security "$TMPDIR/dm_security.json" \
  --slurpfile dm_qa "$TMPDIR/dm_qa.json" \
  --slurpfile dm_vp "$TMPDIR/dm_vp.json" \
  --slurpfile dm_product "$TMPDIR/dm_product.json" \
  --slurpfile dm_sales "$TMPDIR/dm_sales.json" \
  --slurpfile dm_devops "$TMPDIR/dm_devops.json" \
  --slurpfile rv4_admin_msgs "$TMPDIR/rv4_admin_msgs.json" \
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
    blocker_threads: {
      db_migration: $msg1_threads[0],
      security_scan: $msg2_threads[0],
      e2e_tests: $msg3_threads[0]
    },
    direct_messages: {
      backend_lead: $dm_backend[0],
      security_eng: $dm_security[0],
      qa_lead: $dm_qa[0],
      vp_engineering: $dm_vp[0],
      product_manager: $dm_product[0],
      sales_lead: $dm_sales[0],
      devops_lead: $dm_devops[0]
    },
    release_channel_admin_messages: $rv4_admin_msgs[0]
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
echo "Coord channel found: ${CC_FOUND}, name: ${CC_NAME:-none}"
