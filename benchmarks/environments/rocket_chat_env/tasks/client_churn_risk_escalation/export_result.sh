#!/bin/bash
set -euo pipefail

echo "=== Exporting client_churn_risk_escalation result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="client_churn_risk_escalation"
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
CS_MSG1_ID=$(echo "$BASELINE" | jq -r '.cs_msg1_id // empty')
CS_MSG2_ID=$(echo "$BASELINE" | jq -r '.cs_msg2_id // empty')

# Find new private groups (escalation/retention channels)
ALL_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[] | {name: .name, id: ._id, topic: (.topic // "")}]' 2>/dev/null || echo '[]')
echo "$ALL_GROUPS" > "$TMPDIR/all_groups.json"
echo "$BASELINE_GROUPS" > "$TMPDIR/baseline_groups.json"

python3 << 'PYEOF'
import json, os

tmpdir = os.environ.get('TMPDIR', '/tmp/client_churn_risk_escalation_export')
all_groups = json.load(open(f'{tmpdir}/all_groups.json'))
baseline_groups = json.load(open(f'{tmpdir}/baseline_groups.json'))
baseline_set = set(baseline_groups)

new_groups = [g for g in all_groups if g['name'] not in baseline_set]

# Score for escalation channel (internal retention/escalation channel)
escalation_kw = ['meridian', 'escalat', 'churn', 'retent', 'renewal', 'account', 'risk', 'urgent', 'client']

best_group = None
best_score = -1
for g in new_groups:
    name_lower = g['name'].lower()
    topic_lower = (g.get('topic') or '').lower()
    s = sum(1 for kw in escalation_kw if kw in name_lower or kw in topic_lower)
    if s > best_score:
        best_score = s
        best_group = g

result = {
    'new_groups': new_groups,
    'escalation_channel': best_group or {},
    'escalation_channel_found': best_group is not None
}

with open(f'{tmpdir}/escalation_channel.json', 'w') as f:
    json.dump(result, f)
PYEOF

ESC_DATA=$(cat "$TMPDIR/escalation_channel.json" 2>/dev/null || echo '{"new_groups":[],"escalation_channel":{},"escalation_channel_found":false}')
EC_ID=$(echo "$ESC_DATA" | jq -r '.escalation_channel.id // empty')
EC_NAME=$(echo "$ESC_DATA" | jq -r '.escalation_channel.name // empty')
EC_FOUND=$(echo "$ESC_DATA" | jq '.escalation_channel_found')
NEW_GROUP_COUNT=$(echo "$ESC_DATA" | jq '.new_groups | length')

echo '[]' > "$TMPDIR/ec_messages.json"
echo '[]' > "$TMPDIR/ec_members.json"
if [ -n "$EC_ID" ]; then
  rc_api GET "groups.history?roomId=${EC_ID}&count=200" | jq '[.messages[] | {msg: .msg, ts: .ts, u: (.u.username // "system")}] // []' > "$TMPDIR/ec_messages.json" 2>/dev/null || true
  rc_api GET "groups.members?roomId=${EC_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/ec_members.json" 2>/dev/null || true
fi

# Thread replies on CS channel messages
echo '[]' > "$TMPDIR/cs_msg1_threads.json"
echo '[]' > "$TMPDIR/cs_msg2_threads.json"
if [ -n "$CS_MSG1_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${CS_MSG1_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/cs_msg1_threads.json" 2>/dev/null || true
fi
if [ -n "$CS_MSG2_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${CS_MSG2_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/cs_msg2_threads.json" 2>/dev/null || true
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

dm_check "cs.manager" "$TMPDIR/dm_cs_manager.json"
dm_check "vp.sales" "$TMPDIR/dm_vp_sales.json"
dm_check "cto.internal" "$TMPDIR/dm_cto.json"
dm_check "product.lead" "$TMPDIR/dm_product.json"
dm_check "exec.sponsor" "$TMPDIR/dm_exec_sponsor.json"
dm_check "support.lead" "$TMPDIR/dm_support.json"

# Admin messages in existing CS/sales channels
CS_CHANNEL_ID=$(echo "$BASELINE" | jq -r '.cs_channel_id // empty')
echo '[]' > "$TMPDIR/cs_admin_msgs.json"
if [ -n "$CS_CHANNEL_ID" ]; then
  rc_api GET "channels.history?roomId=${CS_CHANNEL_ID}&count=200" | \
    jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/cs_admin_msgs.json" 2>/dev/null || true
fi

jq -n \
  --argjson task_start "$TASK_START" \
  --argjson ec_found "$EC_FOUND" \
  --arg ec_name "$EC_NAME" \
  --arg ec_id "$EC_ID" \
  --argjson new_group_count "$NEW_GROUP_COUNT" \
  --slurpfile ec_messages "$TMPDIR/ec_messages.json" \
  --slurpfile ec_members "$TMPDIR/ec_members.json" \
  --slurpfile cs_msg1_threads "$TMPDIR/cs_msg1_threads.json" \
  --slurpfile cs_msg2_threads "$TMPDIR/cs_msg2_threads.json" \
  --slurpfile dm_cs_manager "$TMPDIR/dm_cs_manager.json" \
  --slurpfile dm_vp_sales "$TMPDIR/dm_vp_sales.json" \
  --slurpfile dm_cto "$TMPDIR/dm_cto.json" \
  --slurpfile dm_product "$TMPDIR/dm_product.json" \
  --slurpfile dm_exec_sponsor "$TMPDIR/dm_exec_sponsor.json" \
  --slurpfile dm_support "$TMPDIR/dm_support.json" \
  --slurpfile cs_admin_msgs "$TMPDIR/cs_admin_msgs.json" \
  '{
    task_start: $task_start,
    escalation_channel: {
      found: $ec_found,
      name: $ec_name,
      id: $ec_id,
      messages: $ec_messages[0],
      members: $ec_members[0]
    },
    new_group_count: $new_group_count,
    cs_channel_threads: {
      vp_call_note: $cs_msg1_threads[0],
      requirements_list: $cs_msg2_threads[0]
    },
    direct_messages: {
      cs_manager: $dm_cs_manager[0],
      vp_sales: $dm_vp_sales[0],
      cto_internal: $dm_cto[0],
      product_lead: $dm_product[0],
      exec_sponsor: $dm_exec_sponsor[0],
      support_lead: $dm_support[0]
    },
    cs_channel_admin_messages: $cs_admin_msgs[0]
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
echo "Escalation channel: ${EC_FOUND}, name: ${EC_NAME:-none}"
