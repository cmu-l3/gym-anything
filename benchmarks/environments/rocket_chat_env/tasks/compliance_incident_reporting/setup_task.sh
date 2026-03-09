#!/bin/bash
set -euo pipefail

echo "=== Setting up compliance_incident_reporting task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="compliance_incident_reporting"

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

create_user_if_not_exists "privacy.officer" "Privacy Officer" "privacy.officer@healthcare.local"
create_user_if_not_exists "legal.counsel" "Legal Counsel" "legal.counsel@healthcare.local"
create_user_if_not_exists "it.director" "IT Director" "it.director@healthcare.local"
create_user_if_not_exists "hr.manager" "HR Manager" "hr.manager@healthcare.local"
create_user_if_not_exists "sys.admin" "System Administrator" "sys.admin@healthcare.local"
create_user_if_not_exists "app.developer" "Application Developer" "app.developer@healthcare.local"

# Create #security-monitoring channel and seed messages
SEC_RESP=$(rc_api POST "channels.create" \
  '{"name":"security-monitoring","members":["privacy.officer","it.director","sys.admin","app.developer"],"readOnly":false}')
SEC_ID=$(echo "$SEC_RESP" | jq -r '.channel._id // empty')

if [ -z "$SEC_ID" ]; then
  SEC_INFO=$(rc_api GET "channels.info?roomName=security-monitoring")
  SEC_ID=$(echo "$SEC_INFO" | jq -r '.channel._id // empty')
fi

# Seed realistic security monitoring messages
PHI_ALERT_MSG_ID=""
if [ -n "$SEC_ID" ]; then
  rc_api POST "chat.postMessage" \
    '{"channel":"#security-monitoring","text":"[INFO] Daily SIEM summary: 1,247 events processed, 3 medium-severity alerts, 0 critical. All clear."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#security-monitoring","text":"[WARNING] Unusual outbound data transfer detected from web-app-prod-03. Volume: 2.3GB over 4 hours. Investigating source process."}' >/dev/null
  sleep 0.3

  PHI_ALERT_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#security-monitoring","text":"[CRITICAL] UNAUTHORIZED ACCESS DETECTED: Patient records API endpoint /api/v2/patients/records exposed without authentication. Missing auth middleware on endpoint deployed in build #4891 (2026-03-05 20:00 UTC). Unauthenticated requests from external IP 203.0.113.42 observed from 2026-03-06 02:15 UTC to 08:15 UTC. Estimated affected records: 847 patients. Data accessed includes: patient names, DOBs, medical record numbers, diagnosis codes (ICD-10). Endpoint secured at 08:15 UTC via emergency hotfix. HIPAA breach assessment required immediately."}')
  PHI_ALERT_MSG_ID=$(echo "$PHI_ALERT_RESP" | jq -r '.message._id // empty')
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#security-monitoring","text":"[INFO] Emergency hotfix build #4892 deployed to production. Auth middleware restored on /api/v2/patients/records."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#security-monitoring","text":"[INFO] Firewall rule added to block IP 203.0.113.42 across all edge nodes."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#security-monitoring","text":"[WARNING] Forensic log preservation initiated for web-app-prod-03. Logs secured in /forensics/incident-2026-03-06/."}' >/dev/null
fi

# Create #compliance-log channel and seed messages
COMP_RESP=$(rc_api POST "channels.create" \
  '{"name":"compliance-log","members":["privacy.officer","legal.counsel","it.director"],"readOnly":false}')
COMP_ID=$(echo "$COMP_RESP" | jq -r '.channel._id // empty')

if [ -z "$COMP_ID" ]; then
  COMP_INFO=$(rc_api GET "channels.info?roomName=compliance-log")
  COMP_ID=$(echo "$COMP_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$COMP_ID" ]; then
  rc_api POST "chat.postMessage" \
    '{"channel":"#compliance-log","text":"Compliance log entry 2026-02-28: Q1 HIPAA training completion rate: 94%. Reminder sent to remaining staff."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#compliance-log","text":"Compliance log entry 2026-03-01: Annual risk assessment due date extended to 2026-04-15 per board approval."}' >/dev/null
fi

# Delete any pre-existing incident channel to ensure clean state
rc_api POST "groups.delete" '{"roomName":"hipaa-inc-2026-0306"}' >/dev/null 2>&1 || true
rc_api POST "channels.delete" '{"roomName":"hipaa-inc-2026-0306"}' >/dev/null 2>&1 || true

# Record baseline state
BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[].name] // []' 2>/dev/null || echo '[]')
BASELINE_CHANNELS=$(rc_api GET "channels.list?count=200" | jq '[.channels[].name] // []' 2>/dev/null || echo '[]')

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "phi_alert_msg_id": "${PHI_ALERT_MSG_ID:-}",
  "security_monitoring_id": "${SEC_ID:-}",
  "compliance_log_id": "${COMP_ID:-}",
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
echo "PHI alert message ID: ${PHI_ALERT_MSG_ID:-unknown}"
echo "Security monitoring channel ID: ${SEC_ID:-unknown}"
echo "Compliance log channel ID: ${COMP_ID:-unknown}"
