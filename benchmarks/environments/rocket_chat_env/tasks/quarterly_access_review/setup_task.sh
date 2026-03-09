#!/bin/bash
set -euo pipefail

echo "=== Setting up quarterly_access_review task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="quarterly_access_review"

rm -f "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_start_ts" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_baseline.json" 2>/dev/null || true

if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then break; fi
  sleep 2
done

LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)
TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken')
USERID=$(echo "$LOGIN_RESP" | jq -r '.data.userId')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "ERROR: Failed to get auth token"
  exit 1
fi

rc_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  if [ -n "$data" ]; then
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" -d "$data" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null
  else
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null
  fi
}

create_user_if_not_exists() {
  local username="$1"
  local name="$2"
  local email="$3"
  rc_api POST "users.create" \
    "{\"username\":\"${username}\",\"name\":\"${name}\",\"email\":\"${email}\",\"password\":\"UserPass123!\",\"verified\":true,\"roles\":[\"user\"],\"joinDefaultChannels\":false,\"requirePasswordChange\":false,\"sendWelcomeEmail\":false}" >/dev/null 2>&1 || true
}

# Create all required users
create_user_if_not_exists "finance.manager" "Finance Manager" "finance.manager@company.local"
create_user_if_not_exists "hr.director" "HR Director" "hr.director@company.local"
create_user_if_not_exists "senior.analyst" "Senior Analyst" "senior.analyst@company.local"
create_user_if_not_exists "dev.jones" "Developer Jones" "dev.jones@company.local"
create_user_if_not_exists "dev.wilson" "Developer Wilson" "dev.wilson@company.local"
create_user_if_not_exists "contractor.smith" "Contractor Smith" "contractor.smith@company.local"
create_user_if_not_exists "former.intern" "Former Intern" "former.intern@company.local"

echo "All users created"

# Helper to get user ID
get_user_id() {
  local username="$1"
  rc_api GET "users.info?username=${username}" | jq -r '.user._id // empty' 2>/dev/null
}

# Clean up pre-existing channels to ensure fresh state
rc_api POST "channels.delete" '{"roomName":"finance-reports"}' >/dev/null 2>&1 || true
rc_api POST "channels.delete" '{"roomName":"hr-confidential"}' >/dev/null 2>&1 || true
rc_api POST "channels.delete" '{"roomName":"compliance-announcements"}' >/dev/null 2>&1 || true
rc_api POST "channels.delete" '{"roomName":"access-review-q1-2026"}' >/dev/null 2>&1 || true
rc_api POST "groups.delete" '{"roomName":"finance-reports"}' >/dev/null 2>&1 || true
rc_api POST "groups.delete" '{"roomName":"hr-confidential"}' >/dev/null 2>&1 || true

sleep 1

# Create #compliance-announcements with access policy
rc_api POST "channels.create" \
  '{"name":"compliance-announcements","readOnly":false}' >/dev/null 2>&1 || true

POLICY_MSG="**Q1 2026 Quarterly Access Review - Channel Access Policy**

The following access rules are in effect immediately:

**#finance-reports** (Restricted):
- Authorized members: finance.manager, senior.analyst
- All other users must be removed

**#hr-confidential** (Restricted):
- Authorized members: hr.director, finance.manager
- All other users must be removed

**General Rules:**
- Contractor accounts (contractor.smith) must not have access to any restricted channel
- Former intern accounts (former.intern) must be removed from all channels except #general
- All removals must be documented with an audit trail message in each affected channel
- A summary report must be filed in a dedicated access review channel

Compliance Officer: admin
Review Period: Q1 2026"

rc_api POST "chat.postMessage" \
  "{\"channel\":\"#compliance-announcements\",\"text\":$(echo "$POLICY_MSG" | jq -Rs .)}" >/dev/null

# Create #finance-reports with ALL users (over-provisioned)
ALL_MEMBERS='["finance.manager","senior.analyst","hr.director","dev.jones","dev.wilson","contractor.smith","former.intern"]'
rc_api POST "channels.create" \
  "{\"name\":\"finance-reports\",\"members\":$(echo $ALL_MEMBERS),\"readOnly\":false}" >/dev/null 2>&1

# Seed some messages in finance-reports
rc_api POST "chat.postMessage" \
  '{"channel":"#finance-reports","text":"Q4 2025 revenue report: Total revenue $12.4M, up 15% YoY. Detailed breakdown attached to ticket FIN-2890."}' >/dev/null
rc_api POST "chat.postMessage" \
  '{"channel":"#finance-reports","text":"Budget allocation for Q1 2026 engineering headcount approved. See FIN-3001 for details."}' >/dev/null

# Create #hr-confidential with ALL users (over-provisioned)
rc_api POST "channels.create" \
  "{\"name\":\"hr-confidential\",\"members\":$(echo $ALL_MEMBERS),\"readOnly\":false}" >/dev/null 2>&1

# Seed some messages in hr-confidential
rc_api POST "chat.postMessage" \
  '{"channel":"#hr-confidential","text":"Performance review cycle begins March 15. Manager ratings due by April 1. HR-4520."}' >/dev/null
rc_api POST "chat.postMessage" \
  '{"channel":"#hr-confidential","text":"Salary adjustment proposals for engineering team under review. Confidential until board approval."}' >/dev/null

# Record baseline: which users are in each channel
FINANCE_CH_INFO=$(rc_api GET "channels.info?roomName=finance-reports")
FINANCE_CH_ID=$(echo "$FINANCE_CH_INFO" | jq -r '.channel._id // empty')
FINANCE_MEMBERS="[]"
if [ -n "$FINANCE_CH_ID" ]; then
  FINANCE_MEMBERS=$(rc_api GET "channels.members?roomId=${FINANCE_CH_ID}&count=100" | jq '[.members[].username] // []' 2>/dev/null || echo '[]')
fi

HR_CH_INFO=$(rc_api GET "channels.info?roomName=hr-confidential")
HR_CH_ID=$(echo "$HR_CH_INFO" | jq -r '.channel._id // empty')
HR_MEMBERS="[]"
if [ -n "$HR_CH_ID" ]; then
  HR_MEMBERS=$(rc_api GET "channels.members?roomId=${HR_CH_ID}&count=100" | jq '[.members[].username] // []' 2>/dev/null || echo '[]')
fi

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "finance_channel_id": "${FINANCE_CH_ID:-}",
  "hr_channel_id": "${HR_CH_ID:-}",
  "finance_initial_members": ${FINANCE_MEMBERS},
  "hr_initial_members": ${HR_MEMBERS}
}
EOF

date +%s > "/tmp/${TASK_NAME}_start_ts"

if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

take_screenshot "/tmp/${TASK_NAME}_start.png"

echo "=== Task setup complete ==="
echo "Finance channel ID: ${FINANCE_CH_ID:-unknown}"
echo "HR channel ID: ${HR_CH_ID:-unknown}"
echo "Finance initial members: ${FINANCE_MEMBERS}"
echo "HR initial members: ${HR_MEMBERS}"
