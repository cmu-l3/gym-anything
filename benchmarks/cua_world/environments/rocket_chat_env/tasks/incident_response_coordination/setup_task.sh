#!/bin/bash
set -euo pipefail

echo "=== Setting up incident_response_coordination task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="incident_response_coordination"

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

create_user_if_not_exists "ops.lead" "Operations Lead" "ops.lead@company.local"
create_user_if_not_exists "backend.dev" "Backend Developer" "backend.dev@company.local"
create_user_if_not_exists "dba.admin" "Database Administrator" "dba.admin@company.local"
create_user_if_not_exists "qa.engineer" "QA Engineer" "qa.engineer@company.local"
create_user_if_not_exists "frontend.dev" "Frontend Developer" "frontend.dev@company.local"

# Create #production-alerts channel and seed alert messages
ALERTS_RESP=$(rc_api POST "channels.create" \
  '{"name":"production-alerts","members":["ops.lead","backend.dev","dba.admin","qa.engineer","frontend.dev"],"readOnly":false}')
ALERTS_ID=$(echo "$ALERTS_RESP" | jq -r '.channel._id // empty')

if [ -z "$ALERTS_ID" ]; then
  ALERTS_INFO=$(rc_api GET "channels.info?roomName=production-alerts")
  ALERTS_ID=$(echo "$ALERTS_INFO" | jq -r '.channel._id // empty')
fi

# Seed realistic production alert messages
DB_ALERT_MSG_ID=""
if [ -n "$ALERTS_ID" ]; then
  rc_api POST "chat.postMessage" \
    '{"channel":"#production-alerts","text":"[ALERT] CPU usage on web-server-03 exceeded 85% threshold at 13:45 UTC. Auto-scaling triggered successfully. No user impact."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#production-alerts","text":"[ALERT] SSL certificate for api.staging.company.com expires in 7 days. Renewal ticket created: OPS-4521."}' >/dev/null
  sleep 0.3

  DB_ALERT_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#production-alerts","text":"[CRITICAL] Database connection pool exhausted on primary cluster db-prod-01. Active connections: 500/500. Multiple API endpoints returning 503 errors. Affected services: user-auth, payment-gateway, inventory-sync. First detected: 2026-03-06 14:30 UTC. Estimated user impact: ~12,000 active sessions."}')
  DB_ALERT_MSG_ID=$(echo "$DB_ALERT_RESP" | jq -r '.message._id // empty')
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#production-alerts","text":"[WARNING] Disk usage on log-aggregator-02 at 78%. Expected to reach 90% within 48 hours at current ingestion rate. Ticket: OPS-4530."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#production-alerts","text":"[INFO] Scheduled maintenance window for CDN cache purge: 2026-03-07 02:00-04:00 UTC. No user impact expected."}' >/dev/null
fi

# Create #engineering-general channel with some chat
rc_api POST "channels.create" \
  '{"name":"engineering-general","members":["ops.lead","backend.dev","dba.admin","qa.engineer","frontend.dev"],"readOnly":false}' >/dev/null 2>&1 || true

# Delete any pre-existing incident channel to ensure clean state
rc_api POST "groups.delete" '{"roomName":"inc-20260306-db-outage"}' >/dev/null 2>&1 || true
rc_api POST "channels.delete" '{"roomName":"inc-20260306-db-outage"}' >/dev/null 2>&1 || true

# Record baseline state
BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[].name] // []' 2>/dev/null || echo '[]')
BASELINE_CHANNELS=$(rc_api GET "channels.list?count=200" | jq '[.channels[].name] // []' 2>/dev/null || echo '[]')

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "db_alert_msg_id": "${DB_ALERT_MSG_ID:-}",
  "production_alerts_id": "${ALERTS_ID:-}",
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
echo "DB alert message ID: ${DB_ALERT_MSG_ID:-unknown}"
echo "Production alerts channel ID: ${ALERTS_ID:-unknown}"
