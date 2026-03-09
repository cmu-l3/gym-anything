#!/bin/bash
set -euo pipefail

echo "=== Exporting devops_postmortem_action_items result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="devops_postmortem_action_items"
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
PM_MSG1_ID=$(echo "$BASELINE" | jq -r '.pm_msg1_id // empty')
PM_MSG2_ID=$(echo "$BASELINE" | jq -r '.pm_msg2_id // empty')
PM_MSG3_ID=$(echo "$BASELINE" | jq -r '.pm_msg3_id // empty')

# Find new private channels created by the agent (tracking channel)
ALL_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[] | {name: .name, id: ._id, topic: (.topic // ""), fname: (.fname // "")}]' 2>/dev/null || echo '[]')

echo "$ALL_GROUPS" > "$TMPDIR/all_groups.json"
echo "$BASELINE_GROUPS" > "$TMPDIR/baseline_groups.json"

# Use Python to find new groups and score for tracking channel
python3 << 'PYEOF'
import json, os

tmpdir = os.environ.get('TMPDIR', '/tmp/devops_postmortem_action_items_export')
all_groups = json.load(open(f'{tmpdir}/all_groups.json'))
baseline_groups = json.load(open(f'{tmpdir}/baseline_groups.json'))
baseline_set = set(baseline_groups)

new_groups = [g for g in all_groups if g['name'] not in baseline_set]

# Score each new group for being a postmortem action tracking channel
tracking_keywords = [
    'action', 'item', 'track', 'postmortem', 'pm-', 'followup', 'follow-up',
    'remediat', 'task', 'todo', 'owner', 'deadline', 'incident'
]

best_group = None
best_score = -1
for g in new_groups:
    name_lower = g['name'].lower()
    topic_lower = (g.get('topic') or '').lower()
    score = sum(1 for kw in tracking_keywords if kw in name_lower or kw in topic_lower)
    if score > best_score:
        best_score = score
        best_group = g

result = {
    'new_groups': new_groups,
    'tracking_channel': best_group or {},
    'tracking_channel_found': best_group is not None
}

with open(f'{tmpdir}/tracking_channel.json', 'w') as f:
    json.dump(result, f)
PYEOF

TRACKING_DATA=$(cat "$TMPDIR/tracking_channel.json" 2>/dev/null || echo '{"new_groups":[],"tracking_channel":{},"tracking_channel_found":false}')
TC_ID=$(echo "$TRACKING_DATA" | jq -r '.tracking_channel.id // empty')
TC_NAME=$(echo "$TRACKING_DATA" | jq -r '.tracking_channel.name // empty')
TC_FOUND=$(echo "$TRACKING_DATA" | jq '.tracking_channel_found')
NEW_GROUP_COUNT=$(echo "$TRACKING_DATA" | jq '.new_groups | length')

# Get tracking channel messages
echo '[]' > "$TMPDIR/tc_messages.json"
echo '[]' > "$TMPDIR/tc_members.json"
if [ -n "$TC_ID" ]; then
  rc_api GET "groups.history?roomId=${TC_ID}&count=200" | jq '[.messages[] | {msg: .msg, ts: .ts, u: (.u.username // "system")}] // []' > "$TMPDIR/tc_messages.json" 2>/dev/null || true
  rc_api GET "groups.members?roomId=${TC_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/tc_members.json" 2>/dev/null || true
fi

# Also scan all new channels' messages for action item content (agent may use an existing channel)
echo '[]' > "$TMPDIR/all_new_msgs.json"
python3 << 'PYEOF2'
import json, os, subprocess

tmpdir = os.environ.get('TMPDIR', '/tmp/devops_postmortem_action_items_export')
tracking_data = json.load(open(f'{tmpdir}/tracking_channel.json'))
new_groups = tracking_data['new_groups']

# Combine all messages from all new groups
all_msgs = []
try:
    existing_msgs = json.load(open(f'{tmpdir}/tc_messages.json'))
    all_msgs.extend(existing_msgs)
except:
    pass

with open(f'{tmpdir}/all_new_msgs.json', 'w') as f:
    json.dump(all_msgs, f)
PYEOF2

# Thread replies on postmortem messages (did agent respond to each postmortem?)
echo '[]' > "$TMPDIR/pm1_threads.json"
echo '[]' > "$TMPDIR/pm2_threads.json"
echo '[]' > "$TMPDIR/pm3_threads.json"

if [ -n "$PM_MSG1_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${PM_MSG1_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/pm1_threads.json" 2>/dev/null || true
fi
if [ -n "$PM_MSG2_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${PM_MSG2_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/pm2_threads.json" 2>/dev/null || true
fi
if [ -n "$PM_MSG3_ID" ]; then
  rc_api GET "chat.getThreadMessages?tmid=${PM_MSG3_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/pm3_threads.json" 2>/dev/null || true
fi

# DMs to each action owner
check_dm() {
  local username="$1"
  local outfile="$2"
  echo '[]' > "$outfile"
  local dm_resp
  dm_resp=$(rc_api POST "im.create" "{\"username\":\"${username}\"}")
  local dm_id
  dm_id=$(echo "$dm_resp" | jq -r '.room._id // empty')
  if [ -n "$dm_id" ]; then
    rc_api GET "im.history?roomId=${dm_id}&count=50" | \
      jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$outfile" 2>/dev/null || true
  fi
}

check_dm "sre.lead" "$TMPDIR/dm_sre_lead.json"
check_dm "backend.dev" "$TMPDIR/dm_backend_dev.json"
check_dm "platform.eng" "$TMPDIR/dm_platform_eng.json"
check_dm "frontend.dev" "$TMPDIR/dm_frontend_dev.json"
check_dm "ops.lead" "$TMPDIR/dm_ops_lead.json"
check_dm "devops.eng" "$TMPDIR/dm_devops_eng.json"
check_dm "dba.eng" "$TMPDIR/dm_dba_eng.json"

# Also check #engineering-postmortems for admin messages (cataloguing in existing channel)
PM_CHANNEL_ID=$(echo "$BASELINE" | jq -r '.pm_channel_id // empty')
echo '[]' > "$TMPDIR/pm_channel_admin_msgs.json"
if [ -n "$PM_CHANNEL_ID" ]; then
  rc_api GET "channels.history?roomId=${PM_CHANNEL_ID}&count=200" | \
    jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/pm_channel_admin_msgs.json" 2>/dev/null || true
fi

# Assemble result
jq -n \
  --argjson task_start "$TASK_START" \
  --argjson tc_found "$TC_FOUND" \
  --arg tc_name "$TC_NAME" \
  --arg tc_id "$TC_ID" \
  --argjson new_group_count "$NEW_GROUP_COUNT" \
  --slurpfile tc_messages "$TMPDIR/tc_messages.json" \
  --slurpfile tc_members "$TMPDIR/tc_members.json" \
  --slurpfile pm1_threads "$TMPDIR/pm1_threads.json" \
  --slurpfile pm2_threads "$TMPDIR/pm2_threads.json" \
  --slurpfile pm3_threads "$TMPDIR/pm3_threads.json" \
  --slurpfile dm_sre_lead "$TMPDIR/dm_sre_lead.json" \
  --slurpfile dm_backend_dev "$TMPDIR/dm_backend_dev.json" \
  --slurpfile dm_platform_eng "$TMPDIR/dm_platform_eng.json" \
  --slurpfile dm_frontend_dev "$TMPDIR/dm_frontend_dev.json" \
  --slurpfile dm_ops_lead "$TMPDIR/dm_ops_lead.json" \
  --slurpfile dm_devops_eng "$TMPDIR/dm_devops_eng.json" \
  --slurpfile dm_dba_eng "$TMPDIR/dm_dba_eng.json" \
  --slurpfile pm_channel_admin_msgs "$TMPDIR/pm_channel_admin_msgs.json" \
  '{
    task_start: $task_start,
    tracking_channel: {
      found: $tc_found,
      name: $tc_name,
      id: $tc_id,
      messages: $tc_messages[0],
      members: $tc_members[0]
    },
    new_group_count: $new_group_count,
    postmortem_threads: {
      incident_047: $pm1_threads[0],
      incident_061: $pm2_threads[0],
      incident_079: $pm3_threads[0]
    },
    direct_messages: {
      sre_lead: $dm_sre_lead[0],
      backend_dev: $dm_backend_dev[0],
      platform_eng: $dm_platform_eng[0],
      frontend_dev: $dm_frontend_dev[0],
      ops_lead: $dm_ops_lead[0],
      devops_eng: $dm_devops_eng[0],
      dba_eng: $dm_dba_eng[0]
    },
    pm_channel_admin_messages: $pm_channel_admin_msgs[0]
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
echo "Tracking channel found: ${TC_FOUND}, name: ${TC_NAME:-none}"
