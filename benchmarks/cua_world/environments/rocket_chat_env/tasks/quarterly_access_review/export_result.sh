#!/bin/bash
set -euo pipefail

echo "=== Exporting quarterly_access_review result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="quarterly_access_review"
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
FINANCE_CH_ID=$(echo "$BASELINE" | jq -r '.finance_channel_id // empty')
HR_CH_ID=$(echo "$BASELINE" | jq -r '.hr_channel_id // empty')

# Save initial members from baseline
echo "$BASELINE" | jq '.finance_initial_members // []' > "$TMPDIR/fin_initial.json" 2>/dev/null || echo '[]' > "$TMPDIR/fin_initial.json"
echo "$BASELINE" | jq '.hr_initial_members // []' > "$TMPDIR/hr_initial.json" 2>/dev/null || echo '[]' > "$TMPDIR/hr_initial.json"

# Current finance-reports members and messages
echo '[]' > "$TMPDIR/fin_current.json"
echo '[]' > "$TMPDIR/fin_messages.json"
if [ -n "$FINANCE_CH_ID" ]; then
  rc_api GET "channels.members?roomId=${FINANCE_CH_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/fin_current.json" 2>/dev/null || true
  rc_api GET "channels.history?roomId=${FINANCE_CH_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/fin_messages.json" 2>/dev/null || true
fi

# Current hr-confidential members and messages
echo '[]' > "$TMPDIR/hr_current.json"
echo '[]' > "$TMPDIR/hr_messages.json"
if [ -n "$HR_CH_ID" ]; then
  rc_api GET "channels.members?roomId=${HR_CH_ID}&count=100" | jq '[.members[].username] // []' > "$TMPDIR/hr_current.json" 2>/dev/null || true
  rc_api GET "channels.history?roomId=${HR_CH_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts, u: .u.username}] // []' > "$TMPDIR/hr_messages.json" 2>/dev/null || true
fi

# Access review channel
REVIEW_EXISTS=false
echo '[]' > "$TMPDIR/review_messages.json"
CH_RESP=$(rc_api GET "channels.info?roomName=access-review-q1-2026")
if echo "$CH_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
  REVIEW_EXISTS=true
  REVIEW_ID=$(echo "$CH_RESP" | jq -r '.channel._id // empty')
  if [ -n "$REVIEW_ID" ]; then
    rc_api GET "channels.history?roomId=${REVIEW_ID}&count=50" | jq '[.messages[] | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/review_messages.json" 2>/dev/null || true
  fi
fi

# DMs to contractor.smith
echo '[]' > "$TMPDIR/contractor_dm.json"
DM_RESP=$(rc_api POST "im.create" '{"username":"contractor.smith"}')
DM_ROOM_ID=$(echo "$DM_RESP" | jq -r '.room._id // empty')
if [ -n "$DM_ROOM_ID" ]; then
  rc_api GET "im.history?roomId=${DM_ROOM_ID}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/contractor_dm.json" 2>/dev/null || true
fi

# DMs to former.intern
echo '[]' > "$TMPDIR/intern_dm.json"
DM_RESP2=$(rc_api POST "im.create" '{"username":"former.intern"}')
DM_ROOM_ID2=$(echo "$DM_RESP2" | jq -r '.room._id // empty')
if [ -n "$DM_ROOM_ID2" ]; then
  rc_api GET "im.history?roomId=${DM_ROOM_ID2}&count=50" | jq '[.messages[] | select(.u.username == "admin") | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/intern_dm.json" 2>/dev/null || true
fi

# Assemble final JSON
jq -n \
  --argjson task_start "$TASK_START" \
  --slurpfile fin_initial "$TMPDIR/fin_initial.json" \
  --slurpfile fin_current "$TMPDIR/fin_current.json" \
  --slurpfile fin_messages "$TMPDIR/fin_messages.json" \
  --slurpfile hr_initial "$TMPDIR/hr_initial.json" \
  --slurpfile hr_current "$TMPDIR/hr_current.json" \
  --slurpfile hr_messages "$TMPDIR/hr_messages.json" \
  --argjson review_exists "$REVIEW_EXISTS" \
  --slurpfile review_messages "$TMPDIR/review_messages.json" \
  --slurpfile contractor_dm "$TMPDIR/contractor_dm.json" \
  --slurpfile intern_dm "$TMPDIR/intern_dm.json" \
  '{
    task_start: $task_start,
    finance_reports: {
      initial_members: $fin_initial[0],
      current_members: $fin_current[0],
      messages: $fin_messages[0]
    },
    hr_confidential: {
      initial_members: $hr_initial[0],
      current_members: $hr_current[0],
      messages: $hr_messages[0]
    },
    review_channel: {
      exists: $review_exists,
      messages: $review_messages[0]
    },
    contractor_dm: $contractor_dm[0],
    intern_dm: $intern_dm[0]
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
echo "=== Export complete ==="
