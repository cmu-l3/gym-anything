#!/bin/bash
set -euo pipefail

echo "=== Exporting compliance_audit_remediation result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="compliance_audit_remediation"
TASK_START_TIME=$(cat "/tmp/${TASK_NAME}_start_ts" 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)
TMPDIR=$(mktemp -d /tmp/export_car.XXXXXX)

take_screenshot "/tmp/${TASK_NAME}_final.png"

# ── Authenticate ──────────────────────────────────────────────────────────
LOGIN_JSON=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

TOKEN=$(echo "$LOGIN_JSON" | jq -r '.data.authToken // empty')
USERID=$(echo "$LOGIN_JSON" | jq -r '.data.userId // empty')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo '{"error":"auth_failed","task_start":'"$TASK_START_TIME"',"task_end":'"$TASK_END_TIME"'}' \
    > "/tmp/${TASK_NAME}_result.json"
  chmod 666 "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true
  exit 0
fi

rc_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  if [ -n "$data" ]; then
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" \
      -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null || echo '{}'
  else
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" \
      -H "X-User-Id: $USERID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null || echo '{}'
  fi
}

# ── Read baseline ─────────────────────────────────────────────────────────
BASELINE=$(cat "/tmp/${TASK_NAME}_baseline.json" 2>/dev/null || echo '{}')
FC_ID=$(echo "$BASELINE" | jq -r '.finance_confidential_id // empty')
HC_ID=$(echo "$BASELINE" | jq -r '.hr_confidential_id // empty')
EU_ID=$(echo "$BASELINE" | jq -r '.executive_updates_id // empty')

# ══════════════════════════════════════════════════════════════════════════
#  1. CHECK #finance-confidential MEMBERS (CA-001)
# ══════════════════════════════════════════════════════════════════════════
echo "Checking #finance-confidential members..."
FC_MEMBERS_JSON="[]"
if [ -n "$FC_ID" ]; then
  FC_MEMBERS_JSON=$(rc_api GET "channels.members?roomId=${FC_ID}&count=100" | \
    jq -c '[.members[].username]' 2>/dev/null || echo '[]')
fi
echo "$FC_MEMBERS_JSON" > "$TMPDIR/fc_members.json"

# ══════════════════════════════════════════════════════════════════════════
#  2. CHECK #hr-confidential TYPE (CA-002)
# ══════════════════════════════════════════════════════════════════════════
echo "Checking #hr-confidential type..."
HC_TYPE="unknown"
HC_EXISTS="false"

# Try as private group first (desired state after remediation)
HC_GROUP_INFO=$(rc_api GET "groups.info?roomName=hr-confidential")
if echo "$HC_GROUP_INFO" | jq -e '.group._id' >/dev/null 2>&1; then
  HC_TYPE="private"
  HC_EXISTS="true"
else
  # Try as public channel (violated state)
  HC_CHAN_INFO=$(rc_api GET "channels.info?roomName=hr-confidential")
  if echo "$HC_CHAN_INFO" | jq -e '.channel._id' >/dev/null 2>&1; then
    HC_TYPE="public"
    HC_EXISTS="true"
  fi
fi
echo "{\"exists\":$HC_EXISTS,\"type\":\"$HC_TYPE\"}" > "$TMPDIR/hc_type.json"

# ══════════════════════════════════════════════════════════════════════════
#  3. CHECK #finance-confidential RETENTION SETTINGS (DR-001)
# ══════════════════════════════════════════════════════════════════════════
echo "Checking #finance-confidential retention settings..."
FC_RETENTION='{}'
if [ -n "$FC_ID" ]; then
  FC_INFO=$(rc_api GET "channels.info?roomId=${FC_ID}")
  FC_RETENTION=$(echo "$FC_INFO" | jq -c '{
    retentionEnabled: (.channel.retention.enabled // .channel.retentionEnabled // false),
    retentionOverrideGlobal: (.channel.retention.overrideGlobal // .channel.retentionOverrideGlobal // false),
    retentionMaxAge: (.channel.retention.maxAge // .channel.retentionMaxAge // -1),
    retentionExcludePinned: (.channel.retention.excludePinned // .channel.retentionExcludePinned // false),
    retentionFilesOnly: (.channel.retention.filesOnly // .channel.retentionFilesOnly // false)
  }' 2>/dev/null || echo '{}')
fi
echo "$FC_RETENTION" > "$TMPDIR/fc_retention.json"

# ══════════════════════════════════════════════════════════════════════════
#  4. CHECK FILE UPLOAD SETTINGS (FU-001)
# ══════════════════════════════════════════════════════════════════════════
echo "Checking file upload settings..."
MAX_SIZE=$(rc_api GET "settings/FileUpload_MaxFileSize" | jq -r '.value // -1')
WHITELIST=$(rc_api GET "settings/FileUpload_MediaTypeWhiteList" | jq -r '.value // ""')
echo "{\"max_file_size\":$MAX_SIZE,\"media_type_whitelist\":\"$WHITELIST\"}" > "$TMPDIR/file_upload.json"

# ══════════════════════════════════════════════════════════════════════════
#  5. CHECK OMNICHANNEL STATUS (IR-001)
# ══════════════════════════════════════════════════════════════════════════
echo "Checking Omnichannel status..."
LIVECHAT_ENABLED=$(rc_api GET "settings/Livechat_enabled" | jq -r '.value // false')

# Check for "Compliance Reports" department
DEPTS=$(rc_api GET "livechat/department?count=100")
COMP_DEPT=$(echo "$DEPTS" | jq -c '[.departments[] | select(.name == "Compliance Reports")] | .[0] // {}' 2>/dev/null || echo '{}')
COMP_DEPT_ID=$(echo "$COMP_DEPT" | jq -r '._id // empty')

# Check agents assigned to department
DEPT_AGENTS="[]"
if [ -n "$COMP_DEPT_ID" ] && [ "$COMP_DEPT_ID" != "null" ]; then
  DEPT_AGENTS_RAW=$(rc_api GET "livechat/department/${COMP_DEPT_ID}/agents")
  DEPT_AGENTS=$(echo "$DEPT_AGENTS_RAW" | jq -c '[.agents[].username]' 2>/dev/null || echo '[]')
fi

jq -nc \
  --argjson enabled "$LIVECHAT_ENABLED" \
  --argjson dept "$COMP_DEPT" \
  --argjson agents "$DEPT_AGENTS" \
  '{livechat_enabled:$enabled, department:$dept, department_agents:$agents}' \
  > "$TMPDIR/omnichannel.json"

# ══════════════════════════════════════════════════════════════════════════
#  6. CHECK AUDIT TRAIL CHANNEL (compliance-remediation-log-q1-2026)
# ══════════════════════════════════════════════════════════════════════════
echo "Checking audit trail channel..."
AUDIT_EXISTS="false"
AUDIT_TYPE="none"
AUDIT_MEMBERS="[]"
AUDIT_MESSAGES="[]"
AUDIT_PINNED="[]"

# Try as private group first
AUDIT_GROUP=$(rc_api GET "groups.info?roomName=compliance-remediation-log-q1-2026")
if echo "$AUDIT_GROUP" | jq -e '.group._id' >/dev/null 2>&1; then
  AUDIT_EXISTS="true"
  AUDIT_TYPE="private"
  AUDIT_ROOM_ID=$(echo "$AUDIT_GROUP" | jq -r '.group._id')

  AUDIT_MEMBERS=$(rc_api GET "groups.members?roomId=${AUDIT_ROOM_ID}&count=100" | \
    jq -c '[.members[].username]' 2>/dev/null || echo '[]')
  AUDIT_MESSAGES=$(rc_api GET "groups.history?roomId=${AUDIT_ROOM_ID}&count=100" | \
    jq -c '[.messages[] | {msg, pinned: (.pinned // false), ts, u: .u.username}]' 2>/dev/null || echo '[]')
  AUDIT_PINNED=$(rc_api GET "chat.getPinnedMessages?roomId=${AUDIT_ROOM_ID}&count=50" | \
    jq -c '[.messages[] | {msg, ts}]' 2>/dev/null || echo '[]')
else
  # Try as public channel
  AUDIT_CHAN=$(rc_api GET "channels.info?roomName=compliance-remediation-log-q1-2026")
  if echo "$AUDIT_CHAN" | jq -e '.channel._id' >/dev/null 2>&1; then
    AUDIT_EXISTS="true"
    AUDIT_TYPE="public"
    AUDIT_ROOM_ID=$(echo "$AUDIT_CHAN" | jq -r '.channel._id')

    AUDIT_MEMBERS=$(rc_api GET "channels.members?roomId=${AUDIT_ROOM_ID}&count=100" | \
      jq -c '[.members[].username]' 2>/dev/null || echo '[]')
    AUDIT_MESSAGES=$(rc_api GET "channels.history?roomId=${AUDIT_ROOM_ID}&count=100" | \
      jq -c '[.messages[] | {msg, pinned: (.pinned // false), ts, u: .u.username}]' 2>/dev/null || echo '[]')
    AUDIT_PINNED=$(rc_api GET "chat.getPinnedMessages?roomId=${AUDIT_ROOM_ID}&count=50" | \
      jq -c '[.messages[] | {msg, ts}]' 2>/dev/null || echo '[]')
  fi
fi

jq -nc \
  --argjson exists "$AUDIT_EXISTS" \
  --arg type "$AUDIT_TYPE" \
  --argjson members "$AUDIT_MEMBERS" \
  --argjson messages "$AUDIT_MESSAGES" \
  --argjson pinned "$AUDIT_PINNED" \
  '{exists:$exists, type:$type, members:$members, messages:$messages, pinned_messages:$pinned}' \
  > "$TMPDIR/audit_trail.json"

# ══════════════════════════════════════════════════════════════════════════
#  7. CHECK #executive-updates ADMIN MESSAGES
# ══════════════════════════════════════════════════════════════════════════
echo "Checking #executive-updates for admin messages..."
EU_ADMIN_MSGS="[]"
if [ -n "$EU_ID" ]; then
  EU_ADMIN_MSGS=$(rc_api GET "channels.history?roomId=${EU_ID}&count=50" | \
    jq -c "[.messages[] | select(.u.username == \"${ROCKETCHAT_TASK_USERNAME}\") | {msg, ts}]" 2>/dev/null || echo '[]')
fi
echo "$EU_ADMIN_MSGS" > "$TMPDIR/executive_updates.json"

# ══════════════════════════════════════════════════════════════════════════
#  ASSEMBLE FINAL RESULT JSON
# ══════════════════════════════════════════════════════════════════════════
echo "Assembling result JSON..."
jq -nc \
  --arg task_start "$TASK_START_TIME" \
  --arg task_end "$TASK_END_TIME" \
  --slurpfile fc_members "$TMPDIR/fc_members.json" \
  --slurpfile hc_type "$TMPDIR/hc_type.json" \
  --slurpfile fc_retention "$TMPDIR/fc_retention.json" \
  --slurpfile file_upload "$TMPDIR/file_upload.json" \
  --slurpfile omnichannel "$TMPDIR/omnichannel.json" \
  --slurpfile audit_trail "$TMPDIR/audit_trail.json" \
  --slurpfile executive_updates "$TMPDIR/executive_updates.json" \
  '{
    task_start: ($task_start | tonumber),
    task_end: ($task_end | tonumber),
    finance_confidential: {
      members: $fc_members[0],
      retention: $fc_retention[0]
    },
    hr_confidential: $hc_type[0],
    file_upload: $file_upload[0],
    omnichannel: $omnichannel[0],
    audit_trail: $audit_trail[0],
    executive_updates: {
      admin_messages: $executive_updates[0]
    }
  }' > "$TMPDIR/result_final.json"

# Write to final location
rm -f "/tmp/${TASK_NAME}_result.json" 2>/dev/null || sudo rm -f "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true
cp "$TMPDIR/result_final.json" "/tmp/${TASK_NAME}_result.json" 2>/dev/null || \
  sudo cp "$TMPDIR/result_final.json" "/tmp/${TASK_NAME}_result.json"
chmod 666 "/tmp/${TASK_NAME}_result.json" 2>/dev/null || sudo chmod 666 "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true

# Cleanup
rm -rf "$TMPDIR"

echo "Result exported to /tmp/${TASK_NAME}_result.json"
cat "/tmp/${TASK_NAME}_result.json" | jq . 2>/dev/null || cat "/tmp/${TASK_NAME}_result.json"
echo ""
echo "=== Export complete ==="
