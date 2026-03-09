#!/bin/bash
set -euo pipefail

echo "=== Setting up client_onboarding_handoff task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="client_onboarding_handoff"

# Remove stale output files
rm -f "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_start_ts" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_baseline.json" 2>/dev/null || true

# Wait for Rocket.Chat
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# Login as admin
for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

# Get auth tokens
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
      -H "X-Auth-Token: $TOKEN" \
      -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null
  else
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" \
      -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null
  fi
}

# Create required users
create_user_if_not_exists() {
  local username="$1"
  local name="$2"
  local email="$3"

  local resp
  resp=$(rc_api POST "users.create" \
    "{\"username\":\"${username}\",\"name\":\"${name}\",\"email\":\"${email}\",\"password\":\"UserPass123!\",\"verified\":true,\"roles\":[\"user\"],\"joinDefaultChannels\":false,\"requirePasswordChange\":false,\"sendWelcomeEmail\":false}")

  if echo "$resp" | jq -e '.success' >/dev/null 2>&1; then
    echo "Created user: $username"
  else
    echo "User $username may already exist (OK)"
  fi
}

create_user_if_not_exists "solutions.architect" "Solutions Architect" "solutions.architect@company.local"
create_user_if_not_exists "account.manager" "Account Manager" "account.manager@company.local"
create_user_if_not_exists "delivery.lead" "Delivery Lead" "delivery.lead@company.local"
create_user_if_not_exists "ux.designer" "UX Designer" "ux.designer@company.local"
create_user_if_not_exists "data.engineer" "Data Engineer" "data.engineer@company.local"
create_user_if_not_exists "client.sponsor" "Client Sponsor" "client.sponsor@company.local"

# Create #sales-handoffs channel and seed messages
HANDOFFS_RESP=$(rc_api POST "channels.create" \
  '{"name":"sales-handoffs","members":["account.manager"],"readOnly":false}')
HANDOFFS_ID=$(echo "$HANDOFFS_RESP" | jq -r '.channel._id // empty')

if [ -z "$HANDOFFS_ID" ]; then
  HANDOFFS_INFO=$(rc_api GET "channels.info?roomName=sales-handoffs")
  HANDOFFS_ID=$(echo "$HANDOFFS_INFO" | jq -r '.channel._id // empty')
fi

# Seed sales handoff messages
BRIEFING_MSG_ID=""
if [ -n "$HANDOFFS_ID" ]; then
  rc_api POST "chat.postMessage" \
    '{"channel":"#sales-handoffs","text":"Heads up team - Meridian Health Systems deal closed yesterday! $2.4M SOW, 18-month engagement."}' >/dev/null
  sleep 0.3

  BRIEFING_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#sales-handoffs","text":"CLIENT BRIEFING: Meridian Health Systems | 500-bed hospital network in Ohio | Primary contact: Dr. Sarah Chen, VP of Digital Health (s.chen@meridianhealth.org) | SOW: Custom EHR integration platform connecting Epic, Cerner, and their proprietary lab system | Key requirements: (1) HL7 FHIR R4 compliance, (2) Real-time patient data sync across 3 facilities, (3) HIPAA-compliant audit logging, (4) Integration with existing Tableau dashboards | Timeline: Discovery phase Mar-Apr 2026, Build phase May-Oct 2026, UAT Nov 2026, Go-live Jan 2027 | Budget: $2.4M | Risk factors: Legacy lab system has no documented API, Cerner instance is 2 major versions behind | Delivery team recommendation: Need strong HL7/FHIR architect and healthcare data specialist"}')
  BRIEFING_MSG_ID=$(echo "$BRIEFING_RESP" | jq -r '.message._id // empty')
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#sales-handoffs","text":"I'\''ll set up an intro call with Dr. Chen for next week. PM please take over from here."}' >/dev/null
fi

# Create #delivery-standup channel with some chatter
rc_api POST "channels.create" \
  '{"name":"delivery-standup","members":["solutions.architect","delivery.lead","ux.designer","data.engineer"],"readOnly":false}' >/dev/null 2>&1 || true

STANDUP_ID=""
STANDUP_INFO=$(rc_api GET "channels.info?roomName=delivery-standup")
STANDUP_ID=$(echo "$STANDUP_INFO" | jq -r '.channel._id // empty')

if [ -n "$STANDUP_ID" ]; then
  rc_api POST "chat.postMessage" \
    '{"channel":"#delivery-standup","text":"Good morning team. Quick standup: wrapping up the Acme Corp API migration today. On track for Friday delivery."}' >/dev/null
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#delivery-standup","text":"FYI - the staging environment for BlueStar project will be down for maintenance 2-4pm today."}' >/dev/null
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#delivery-standup","text":"Reminder: sprint retro for Project Falcon at 3pm. Please have your notes ready."}' >/dev/null
fi

# Delete any pre-existing project channels to ensure clean state
rc_api POST "groups.delete" '{"roomName":"proj-meridian-internal"}' >/dev/null 2>&1 || true
rc_api POST "channels.delete" '{"roomName":"proj-meridian-internal"}' >/dev/null 2>&1 || true
rc_api POST "groups.delete" '{"roomName":"proj-meridian-client"}' >/dev/null 2>&1 || true
rc_api POST "channels.delete" '{"roomName":"proj-meridian-client"}' >/dev/null 2>&1 || true

# Record baseline state
BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[].name] // []' 2>/dev/null || echo '[]')
BASELINE_CHANNELS=$(rc_api GET "channels.list?count=200" | jq '[.channels[].name] // []' 2>/dev/null || echo '[]')

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "briefing_msg_id": "${BRIEFING_MSG_ID:-}",
  "sales_handoffs_id": "${HANDOFFS_ID:-}",
  "baseline_groups": ${BASELINE_GROUPS},
  "baseline_channels": ${BASELINE_CHANNELS}
}
EOF

# Record task start timestamp
date +%s > "/tmp/${TASK_NAME}_start_ts"

# Restart browser at login page
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
echo "Briefing message ID: ${BRIEFING_MSG_ID:-unknown}"
echo "Sales handoffs channel ID: ${HANDOFFS_ID:-unknown}"
