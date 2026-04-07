#!/bin/bash
set -euo pipefail

echo "=== Setting up compliance_audit_remediation task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="compliance_audit_remediation"

# ── Clean stale output files ─────────────────────────────────────────────
rm -f "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_start_ts"    2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_baseline.json" 2>/dev/null || true

# ── Wait for Rocket.Chat ─────────────────────────────────────────────────
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# ── Authenticate ──────────────────────────────────────────────────────────
echo "Authenticating as admin..."
for attempt in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    echo "API login ready (attempt $attempt)"
    break
  fi
  sleep 2
done

LOGIN_JSON=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login")

TOKEN=$(echo "$LOGIN_JSON" | jq -r '.data.authToken')
USERID=$(echo "$LOGIN_JSON" | jq -r '.data.userId')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "ERROR: Authentication failed"
  exit 1
fi

echo "Authenticated: token=${TOKEN:0:8}... userId=$USERID"

# ── Helper: Authenticated API call ────────────────────────────────────────
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
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}"
  else
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" \
      -H "X-User-Id: $USERID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}"
  fi
}

# ── Helper: Create user if not exists ─────────────────────────────────────
create_user_if_not_exists() {
  local username="$1"
  local name="$2"
  local email="${username}@rocketchat.local"
  local password="UserPass123!"

  local existing
  existing=$(rc_api GET "users.info?username=${username}" 2>/dev/null || echo '{}')
  if echo "$existing" | jq -e '.user._id' >/dev/null 2>&1; then
    echo "User $username already exists"
    return 0
  fi

  local payload
  payload=$(jq -nc \
    --arg u "$username" \
    --arg n "$name" \
    --arg e "$email" \
    --arg p "$password" \
    '{username:$u, name:$n, email:$e, password:$p, roles:["user"], joinDefaultChannels:false, verified:true}')

  local result
  result=$(rc_api POST "users.create" "$payload" 2>/dev/null || echo '{}')
  if echo "$result" | jq -e '.user._id' >/dev/null 2>&1; then
    echo "Created user: $username"
  else
    echo "WARNING: Could not create user $username: $result"
  fi
}

# ── Helper: Post message as a user (via admin, attributed with prefix) ────
post_as() {
  local channel_id="$1"
  local username="$2"
  local text="$3"

  sleep 1
  local payload
  payload=$(jq -nc --arg rid "$channel_id" --arg msg "[${username}]: ${text}" \
    '{message:{rid:$rid, msg:$msg}}')
  rc_api POST "chat.sendMessage" "$payload" > /dev/null
}

# ── Helper: Post message as admin and capture message ID ──────────────────
post_and_capture() {
  local channel_id="$1"
  local text="$2"

  sleep 1
  local payload
  payload=$(jq -nc --arg rid "$channel_id" --arg msg "$text" \
    '{message:{rid:$rid, msg:$msg}}')
  local result
  result=$(rc_api POST "chat.sendMessage" "$payload")
  echo "$result" | jq -r '.message._id // empty'
}

# ── Helper: Delete channel (try both group and channel) ───────────────────
delete_channel_if_exists() {
  local ch_name="$1"
  local gid cid

  gid=$(rc_api GET "groups.info?roomName=${ch_name}" 2>/dev/null | jq -r '.group._id // empty') || true
  if [ -n "$gid" ] && [ "$gid" != "null" ]; then
    rc_api POST "groups.delete" "{\"roomId\":\"$gid\"}" >/dev/null 2>&1 || true
    echo "  Deleted group: $ch_name"
  fi

  cid=$(rc_api GET "channels.info?roomName=${ch_name}" 2>/dev/null | jq -r '.channel._id // empty') || true
  if [ -n "$cid" ] && [ "$cid" != "null" ]; then
    rc_api POST "channels.delete" "{\"roomId\":\"$cid\"}" >/dev/null 2>&1 || true
    echo "  Deleted channel: $ch_name"
  fi
}

# ══════════════════════════════════════════════════════════════════════════
#  1. CREATE USERS
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "Creating users..."
create_user_if_not_exists "ciso"               "Raj Venkataraman - CISO"
create_user_if_not_exists "compliance.officer"  "Elena Vasquez - Compliance Officer"
create_user_if_not_exists "legal.counsel"       "Adrienne Moreau - Legal Counsel"
create_user_if_not_exists "contractor.davis"    "Mike Davis - External Contractor"
create_user_if_not_exists "intern.patel"        "Anika Patel - Summer Intern"
create_user_if_not_exists "finance.director"    "James Chen - Finance Director"

# ══════════════════════════════════════════════════════════════════════════
#  2. CLEAN SLATE: Delete all channels that the agent might create/modify
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "Cleaning up pre-existing channels..."
for ch_name in \
  compliance-remediation-log-q1-2026 \
  compliance-remediation-log \
  compliance-audit-findings \
  it-security-policy \
  hr-operations \
  finance-confidential \
  hr-confidential \
  executive-updates \
  breach-notification-draft; do
  delete_channel_if_exists "$ch_name"
done

# ══════════════════════════════════════════════════════════════════════════
#  3. RESET ADMIN SETTINGS TO "VIOLATED" STATE
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "Resetting admin settings to violated state..."

# File Upload: permissive defaults (VIOLATED -- no restrictions)
rc_api POST "settings/FileUpload_MaxFileSize" '{"value": 104857600}' > /dev/null      # 100MB
rc_api POST "settings/FileUpload_MediaTypeWhiteList" '{"value": ""}' > /dev/null       # Allow all
rc_api POST "settings/FileUpload_MediaTypeBlackList" '{"value": ""}' > /dev/null       # No blocks

# Retention Policy: enable globally so per-room overrides are POSSIBLE,
# but set global max age very high so nothing actually gets pruned.
# The violation is that #finance-confidential has NO per-room override.
rc_api POST "settings/RetentionPolicy_Enabled" '{"value": true}' > /dev/null
rc_api POST "settings/RetentionPolicy_AppliesToChannels" '{"value": true}' > /dev/null
rc_api POST "settings/RetentionPolicy_AppliesToGroups" '{"value": true}' > /dev/null
rc_api POST "settings/RetentionPolicy_MaxAge_Channels" '{"value": 36500}' > /dev/null  # ~100 years
rc_api POST "settings/RetentionPolicy_MaxAge_Groups" '{"value": 36500}' > /dev/null
rc_api POST "settings/RetentionPolicy_ExcludePinned" '{"value": false}' > /dev/null

# Omnichannel: disable (VIOLATED -- no compliance reporting workflow)
rc_api POST "settings/Livechat_enabled" '{"value": false}' > /dev/null

# Remove compliance.officer from livechat agents if present
COMP_USER_ID=$(rc_api GET "users.info?username=compliance.officer" 2>/dev/null | jq -r '.user._id // empty')
if [ -n "$COMP_USER_ID" ] && [ "$COMP_USER_ID" != "null" ]; then
  rc_api DELETE "livechat/users/agent/${COMP_USER_ID}" >/dev/null 2>&1 || true
fi

# Remove ALL livechat departments via MongoDB
# (RC 8.1 Community limits department deletion via API)
echo "Clearing Omnichannel departments via MongoDB..."
MONGO_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i mongo | head -1)
if [ -n "$MONGO_CONTAINER" ]; then
  docker exec "$MONGO_CONTAINER" mongosh rocketchat --quiet \
    --eval "db.rocketchat_livechat_department.deleteMany({}); db.rocketchat_livechat_department_agents.deleteMany({});" \
    >/dev/null 2>&1 || true
  echo "  MongoDB department cleanup complete"
else
  echo "  WARNING: Could not find MongoDB container for department cleanup"
fi

echo "Admin settings reset complete."

# ══════════════════════════════════════════════════════════════════════════
#  4. CREATE SOURCE CHANNELS WITH SEEDED MESSAGES
# ══════════════════════════════════════════════════════════════════════════

# ── 4a. #compliance-audit-findings ────────────────────────────────────────
echo ""
echo "Creating #compliance-audit-findings..."
CAF_JSON=$(rc_api POST "channels.create" \
  '{"name":"compliance-audit-findings","members":["ciso","compliance.officer","legal.counsel"]}')
CAF_ID=$(echo "$CAF_JSON" | jq -r '.channel._id // empty')
if [ -z "$CAF_ID" ] || [ "$CAF_ID" = "null" ]; then
  CAF_ID=$(rc_api GET "channels.info?roomName=compliance-audit-findings" | jq -r '.channel._id')
fi
echo "  Channel ID: $CAF_ID"

post_as "$CAF_ID" "compliance.officer" \
  "Q1 2026 Internal Compliance Audit -- Summary of Findings. Audit period: January 1 - March 15, 2026. Auditor: Elena Vasquez, Compliance Officer. Scope: Rocket.Chat workspace access controls, data retention, file upload governance, and incident reporting capabilities."

post_as "$CAF_ID" "compliance.officer" \
  "FINDING CA-001 (HIGH): Channel access violation in #finance-confidential. Users contractor.davis and intern.patel are current members. Per Policy SEC-AC-003, only Finance department permanent employees may access financial data channels. Neither user is a Finance department member -- contractor.davis is an external contractor in Engineering, intern.patel is a summer intern in Marketing. Required action: Remove both users immediately."

post_as "$CAF_ID" "compliance.officer" \
  "FINDING CA-002 (CRITICAL): Channel #hr-confidential is configured as a public channel. This channel contains employee compensation data, performance reviews, and disciplinary records. Per Policy SEC-AC-001, all HR data channels must be private groups with membership restricted to HR department personnel. Required action: Convert to private channel immediately."

post_as "$CAF_ID" "compliance.officer" \
  "FINDING DR-001 (HIGH): Channel #finance-confidential has no retention policy configured. Per Policy SEC-DR-002, financial data channels must have retention enforced. Configure the retention settings as specified in that policy. Additionally, the workspace global file upload settings do not comply with Policy SEC-FU-001 -- the maximum file size is unrestricted and no MIME type filtering is in place. Required action: Configure per-channel retention on #finance-confidential per SEC-DR-002 and update global file upload settings per SEC-FU-001."

post_as "$CAF_ID" "compliance.officer" \
  "FINDING IR-001 (HIGH): The workspace has no internal compliance incident reporting mechanism. Per Policy SEC-IR-001, the organization must maintain an accessible compliance reporting channel using Omnichannel LiveChat. Required action: Enable Omnichannel, create the required department with the correct name, description, and email as specified in Policy SEC-IR-001, and assign the designated compliance officer as a LiveChat agent."

post_as "$CAF_ID" "ciso" \
  "Elena -- excellent and thorough audit. All findings approved for immediate remediation. Priority order: CA-002 (critical exposure), then CA-001, DR-001, IR-001. Please ensure all remediations are documented in a dedicated audit trail channel for our external auditors."

# ── 4b. #it-security-policy ──────────────────────────────────────────────
echo ""
echo "Creating #it-security-policy..."
ISP_JSON=$(rc_api POST "channels.create" \
  '{"name":"it-security-policy","members":["ciso","compliance.officer","legal.counsel","finance.director"]}')
ISP_ID=$(echo "$ISP_JSON" | jq -r '.channel._id // empty')
if [ -z "$ISP_ID" ] || [ "$ISP_ID" = "null" ]; then
  ISP_ID=$(rc_api GET "channels.info?roomName=it-security-policy" | jq -r '.channel._id')
fi
echo "  Channel ID: $ISP_ID"

post_as "$ISP_ID" "ciso" \
  "Policy SEC-AC-001: Channel Classification and Access Control. All channels containing sensitive data (HR, Finance, Legal, Executive) must be configured as private groups. Membership must be restricted to department personnel and authorized cross-functional stakeholders approved in writing by the department head. Quarterly access reviews are mandatory."

post_as "$ISP_ID" "ciso" \
  "Policy SEC-AC-003: Financial Data Access. Access to financial data channels is restricted to permanent full-time employees of the Finance department. Contractors, interns, temporary staff, and cross-department personnel require written authorization from the Finance Director and CISO. No exceptions for read-only access."

post_as "$ISP_ID" "ciso" \
  "Policy SEC-DR-002: Data Retention. Financial data channels: 365-day message retention, exclude pinned messages from automatic pruning. HR data channels: 730-day message retention. General channels: no mandatory retention. Pinned messages containing standing policies or procedures are excluded from automatic pruning in all cases."

post_as "$ISP_ID" "ciso" \
  "Policy SEC-FU-001: File Upload Governance. Maximum upload size: 10MB workspace-wide. Permitted MIME types: image/jpeg, image/png, image/gif, application/pdf, application/vnd.openxmlformats-officedocument.wordprocessingml.document, application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, application/vnd.openxmlformats-officedocument.presentationml.presentation. All other file types must be blocked."

post_as "$ISP_ID" "ciso" \
  'Policy SEC-IR-001: Compliance Incident Reporting. The organization must maintain an Omnichannel LiveChat-based compliance reporting system. Required configuration -- Department name: "Compliance Reports". Department description: "Internal compliance issue reporting and tracking". Department email: "compliance.reports@company.internal". Show on Registration Page: enabled. The compliance.officer user must be assigned as a LiveChat agent in this department to handle incoming compliance reports.'

post_as "$ISP_ID" "legal.counsel" \
  "Confirming all policies referenced above are board-approved as of January 15, 2026. Next review cycle: July 2026."

# ── 4c. #hr-operations ───────────────────────────────────────────────────
echo ""
echo "Creating #hr-operations..."
HRO_JSON=$(rc_api POST "channels.create" \
  '{"name":"hr-operations","members":["compliance.officer","contractor.davis","intern.patel","finance.director"]}')
HRO_ID=$(echo "$HRO_JSON" | jq -r '.channel._id // empty')
if [ -z "$HRO_ID" ] || [ "$HRO_ID" = "null" ]; then
  HRO_ID=$(rc_api GET "channels.info?roomName=hr-operations" | jq -r '.channel._id')
fi
echo "  Channel ID: $HRO_ID"

post_as "$HRO_ID" "compliance.officer" \
  "Current Department Roster -- Q1 2026 Update: Finance Department: james.chen (Finance Director), sarah.wong (Senior Accountant), raj.kumar (Financial Analyst), lisa.park (AP/AR Specialist). Engineering Department: contractor.davis (External Contractor, term ends June 2026), dev.lead (Dev Lead), api.engineer (API Engineer). Marketing Department: intern.patel (Summer Intern, term ends August 2026), marketing.manager (Marketing Manager). Compliance and Legal: compliance.officer (Compliance Officer), legal.counsel (Legal Counsel), ciso (CISO)."

post_as "$HRO_ID" "compliance.officer" \
  "Reminder: Contractor and intern access must be reviewed monthly per Policy SEC-AC-001. All temporary personnel have restricted access profiles. Notify Compliance of any role changes."

# ══════════════════════════════════════════════════════════════════════════
#  5. CREATE TARGET CHANNELS WITH VIOLATIONS IN PLACE
# ══════════════════════════════════════════════════════════════════════════

# ── 5a. #finance-confidential (VIOLATION: contractor.davis + intern.patel are members)
echo ""
echo "Creating #finance-confidential (with access violations)..."
FC_JSON=$(rc_api POST "channels.create" \
  '{"name":"finance-confidential","members":["finance.director","contractor.davis","intern.patel","compliance.officer"]}')
FC_ID=$(echo "$FC_JSON" | jq -r '.channel._id // empty')
if [ -z "$FC_ID" ] || [ "$FC_ID" = "null" ]; then
  FC_ID=$(rc_api GET "channels.info?roomName=finance-confidential" | jq -r '.channel._id')
fi
echo "  Channel ID: $FC_ID"

post_as "$FC_ID" "finance.director" \
  "Q1 budget review meeting moved to Thursday. Please review the attached projections before then."

post_as "$FC_ID" "finance.director" \
  "Vendor payment schedule for March has been finalized. All invoices processed and approved."

# Post a message that will be pinned (standing policy)
PINNED_MSG_ID=$(post_and_capture "$FC_ID" \
  "[compliance.officer]: Standing policy: All financial documents must follow the 4-eye principle. No single approval for transactions over \$5,000. This message is pinned for reference.")

if [ -n "$PINNED_MSG_ID" ] && [ "$PINNED_MSG_ID" != "null" ]; then
  echo "  Pinning standing policy message: $PINNED_MSG_ID"
  rc_api POST "chat.pinMessage" "{\"messageId\":\"$PINNED_MSG_ID\"}" > /dev/null 2>&1 || true
fi

# ── 5b. #hr-confidential (VIOLATION: is PUBLIC, should be PRIVATE) ────────
echo ""
echo "Creating #hr-confidential as PUBLIC channel (violation)..."
HC_JSON=$(rc_api POST "channels.create" \
  '{"name":"hr-confidential","members":["compliance.officer","legal.counsel"]}')
HC_ID=$(echo "$HC_JSON" | jq -r '.channel._id // empty')
if [ -z "$HC_ID" ] || [ "$HC_ID" = "null" ]; then
  HC_ID=$(rc_api GET "channels.info?roomName=hr-confidential" | jq -r '.channel._id')
fi
echo "  Channel ID: $HC_ID (type: public -- this is the violation)"

post_as "$HC_ID" "compliance.officer" \
  "Employee performance review cycle begins April 1. Managers to submit reviews by April 15."

post_as "$HC_ID" "legal.counsel" \
  "Updated disciplinary procedure documentation has been uploaded to the HR portal."

# ══════════════════════════════════════════════════════════════════════════
#  6. CREATE #executive-updates
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "Creating #executive-updates..."
EU_JSON=$(rc_api POST "channels.create" \
  '{"name":"executive-updates","members":["ciso","compliance.officer","legal.counsel","finance.director"]}')
EU_ID=$(echo "$EU_JSON" | jq -r '.channel._id // empty')
if [ -z "$EU_ID" ] || [ "$EU_ID" = "null" ]; then
  EU_ID=$(rc_api GET "channels.info?roomName=executive-updates" | jq -r '.channel._id')
fi
echo "  Channel ID: $EU_ID"

post_as "$EU_ID" "ciso" \
  "All department heads: Q1 compliance audit is underway. Expect remediation items by end of week. Full compliance status will be reported to the board at the April meeting."

# ══════════════════════════════════════════════════════════════════════════
#  7. SAVE BASELINE
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "Saving baseline..."

# Record initial finance-confidential members for do-nothing gate
FC_MEMBERS=$(rc_api GET "channels.members?roomId=${FC_ID}&count=100" 2>/dev/null | \
  jq -c '[.members[].username]' 2>/dev/null || echo '[]')

BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" 2>/dev/null | \
  jq -c '[.groups[].name]' 2>/dev/null || echo '[]')
BASELINE_CHANNELS=$(rc_api GET "channels.list?count=200" 2>/dev/null | \
  jq -c '[.channels[].name]' 2>/dev/null || echo '[]')

jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg caf_id "$CAF_ID" \
  --arg isp_id "$ISP_ID" \
  --arg hro_id "$HRO_ID" \
  --arg fc_id "$FC_ID" \
  --arg hc_id "$HC_ID" \
  --arg eu_id "$EU_ID" \
  --argjson fc_members "$FC_MEMBERS" \
  --argjson baseline_groups "$BASELINE_GROUPS" \
  --argjson baseline_channels "$BASELINE_CHANNELS" \
  '{
    task_start: $ts,
    compliance_audit_findings_id: $caf_id,
    it_security_policy_id: $isp_id,
    hr_operations_id: $hro_id,
    finance_confidential_id: $fc_id,
    hr_confidential_id: $hc_id,
    executive_updates_id: $eu_id,
    initial_finance_members: $fc_members,
    baseline_groups: $baseline_groups,
    baseline_channels: $baseline_channels
  }' > "/tmp/${TASK_NAME}_baseline.json"

echo "Baseline saved to /tmp/${TASK_NAME}_baseline.json"

# ══════════════════════════════════════════════════════════════════════════
#  8. RECORD START TIMESTAMP & LAUNCH BROWSER
# ══════════════════════════════════════════════════════════════════════════
date +%s > "/tmp/${TASK_NAME}_start_ts"

echo ""
echo "Launching browser..."
restart_firefox "${ROCKETCHAT_LOGIN_URL}" 5
focus_firefox
maximize_active_window
sleep 2
take_screenshot "/tmp/${TASK_NAME}_initial.png"

echo ""
echo "=== compliance_audit_remediation task setup complete ==="
echo "  Users: ciso, compliance.officer, legal.counsel, contractor.davis, intern.patel, finance.director"
echo "  Source channels: #compliance-audit-findings, #it-security-policy, #hr-operations"
echo "  Violated channels: #finance-confidential (wrong members), #hr-confidential (public)"
echo "  Global violations: file upload unrestricted, Omnichannel disabled"
echo "  Agent must: fix access, convert channel, configure retention, configure uploads,"
echo "              set up Omnichannel + department + agent, create audit trail"
