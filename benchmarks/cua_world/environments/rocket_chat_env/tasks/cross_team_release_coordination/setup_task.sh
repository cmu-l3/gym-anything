#!/bin/bash
set -euo pipefail

echo "=== Setting up cross_team_release_coordination task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="cross_team_release_coordination"

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

create_user_if_not_exists "vp.engineering" "VP of Engineering" "vp.engineering@company.local"
create_user_if_not_exists "frontend.lead" "Frontend Team Lead" "frontend.lead@company.local"
create_user_if_not_exists "backend.lead" "Backend Team Lead" "backend.lead@company.local"
create_user_if_not_exists "payments.lead" "Payments Team Lead" "payments.lead@company.local"
create_user_if_not_exists "infra.lead" "Infrastructure Lead" "infra.lead@company.local"
create_user_if_not_exists "qa.lead" "QA Lead" "qa.lead@company.local"

# --- Create #team-frontend channel and seed pre-release checklist ---
FRONTEND_RESP=$(rc_api POST "channels.create" \
  '{"name":"team-frontend","members":["frontend.lead","qa.lead"],"readOnly":false}')
FRONTEND_ID=$(echo "$FRONTEND_RESP" | jq -r '.channel._id // empty')

if [ -z "$FRONTEND_ID" ]; then
  FRONTEND_INFO=$(rc_api GET "channels.info?roomName=team-frontend")
  FRONTEND_ID=$(echo "$FRONTEND_INFO" | jq -r '.channel._id // empty')
fi

FRONTEND_CHECKLIST_MSG_ID=""
if [ -n "$FRONTEND_ID" ]; then
  FRONTEND_MSG_RESP=$(rc_api POST "chat.postMessage" \
    "{\"channel\":\"#team-frontend\",\"text\":\"PRE-RELEASE CHECKLIST v3.0 - Frontend Team:\\n- [x] Asset bundle optimization complete (bundle size: 1.2MB -> 890KB)\\n- [x] CDN cache invalidation script tested\\n- [x] Feature flags configured for gradual rollout\\n- [ ] Cross-browser regression suite: PENDING (ETA: 2026-03-06 18:00 UTC)\\n- [x] Rollback procedure documented\\nStatus: CONDITIONAL GO - pending cross-browser tests\"}")
  FRONTEND_CHECKLIST_MSG_ID=$(echo "$FRONTEND_MSG_RESP" | jq -r '.message._id // empty')
fi
sleep 0.3

# --- Create #team-backend channel and seed pre-release checklist ---
BACKEND_RESP=$(rc_api POST "channels.create" \
  '{"name":"team-backend","members":["backend.lead","qa.lead"],"readOnly":false}')
BACKEND_ID=$(echo "$BACKEND_RESP" | jq -r '.channel._id // empty')

if [ -z "$BACKEND_ID" ]; then
  BACKEND_INFO=$(rc_api GET "channels.info?roomName=team-backend")
  BACKEND_ID=$(echo "$BACKEND_INFO" | jq -r '.channel._id // empty')
fi

BACKEND_CHECKLIST_MSG_ID=""
if [ -n "$BACKEND_ID" ]; then
  BACKEND_MSG_RESP=$(rc_api POST "chat.postMessage" \
    "{\"channel\":\"#team-backend\",\"text\":\"PRE-RELEASE CHECKLIST v3.0 - Backend Team:\\n- [x] Database migration scripts reviewed and tested on staging\\n- [x] API backward compatibility verified for v2.x clients\\n- [x] Rate limiting updated for new endpoints\\n- [x] Load test passed: 15,000 RPS sustained for 30 minutes\\n- [x] Rollback procedure: blue-green deployment switch\\nStatus: GO\"}")
  BACKEND_CHECKLIST_MSG_ID=$(echo "$BACKEND_MSG_RESP" | jq -r '.message._id // empty')
fi
sleep 0.3

# --- Create #team-payments channel and seed pre-release checklist ---
PAYMENTS_RESP=$(rc_api POST "channels.create" \
  '{"name":"team-payments","members":["payments.lead","qa.lead"],"readOnly":false}')
PAYMENTS_ID=$(echo "$PAYMENTS_RESP" | jq -r '.channel._id // empty')

if [ -z "$PAYMENTS_ID" ]; then
  PAYMENTS_INFO=$(rc_api GET "channels.info?roomName=team-payments")
  PAYMENTS_ID=$(echo "$PAYMENTS_INFO" | jq -r '.channel._id // empty')
fi

PAYMENTS_CHECKLIST_MSG_ID=""
if [ -n "$PAYMENTS_ID" ]; then
  PAYMENTS_MSG_RESP=$(rc_api POST "chat.postMessage" \
    "{\"channel\":\"#team-payments\",\"text\":\"PRE-RELEASE CHECKLIST v3.0 - Payments Team:\\n- [x] PCI-DSS compliance scan passed\\n- [x] New Stripe webhook handlers tested with sandbox\\n- [x] Refund flow regression tests passed\\n- [x] Payment reconciliation job updated for new schema\\n- [x] Rollback procedure: feature flag kill switch + DB rollback script\\nStatus: GO\"}")
  PAYMENTS_CHECKLIST_MSG_ID=$(echo "$PAYMENTS_MSG_RESP" | jq -r '.message._id // empty')
fi
sleep 0.3

# --- Create #team-infra channel and seed pre-release checklist ---
INFRA_RESP=$(rc_api POST "channels.create" \
  '{"name":"team-infra","members":["infra.lead","qa.lead"],"readOnly":false}')
INFRA_ID=$(echo "$INFRA_RESP" | jq -r '.channel._id // empty')

if [ -z "$INFRA_ID" ]; then
  INFRA_INFO=$(rc_api GET "channels.info?roomName=team-infra")
  INFRA_ID=$(echo "$INFRA_INFO" | jq -r '.channel._id // empty')
fi

INFRA_CHECKLIST_MSG_ID=""
if [ -n "$INFRA_ID" ]; then
  INFRA_MSG_RESP=$(rc_api POST "chat.postMessage" \
    "{\"channel\":\"#team-infra\",\"text\":\"PRE-RELEASE CHECKLIST v3.0 - Infrastructure Team:\\n- [x] Kubernetes manifests updated for v3.0 containers\\n- [x] Auto-scaling policies configured (min 6, max 24 pods)\\n- [x] Monitoring dashboards updated with v3.0 metrics\\n- [x] DNS failover tested\\n- [x] Rollback procedure: kubectl rollout undo + DNS switch\\nStatus: GO\"}")
  INFRA_CHECKLIST_MSG_ID=$(echo "$INFRA_MSG_RESP" | jq -r '.message._id // empty')
fi
sleep 0.3

# --- Create #release-announcements channel with all members and seed past notices ---
ANNOUNCE_RESP=$(rc_api POST "channels.create" \
  '{"name":"release-announcements","members":["vp.engineering","frontend.lead","backend.lead","payments.lead","infra.lead","qa.lead"],"readOnly":false}')
ANNOUNCE_ID=$(echo "$ANNOUNCE_RESP" | jq -r '.channel._id // empty')

if [ -z "$ANNOUNCE_ID" ]; then
  ANNOUNCE_INFO=$(rc_api GET "channels.info?roomName=release-announcements")
  ANNOUNCE_ID=$(echo "$ANNOUNCE_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$ANNOUNCE_ID" ]; then
  rc_api POST "chat.postMessage" \
    '{"channel":"#release-announcements","text":"[RELEASE NOTICE] Platform v2.8 has been successfully deployed to production. All systems nominal. No rollback required. Thanks to all teams for a smooth release! - Release Management"}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#release-announcements","text":"[RELEASE NOTICE] Platform v2.9 deployment completed. Minor issue with CDN cache propagation resolved within 15 minutes. Post-mortem scheduled for Friday. - Release Management"}' >/dev/null
  sleep 0.3
fi

# --- Delete any pre-existing release-v3-coordination channel ---
rc_api POST "channels.delete" '{"roomName":"release-v3-coordination"}' >/dev/null 2>&1 || true
rc_api POST "groups.delete" '{"roomName":"release-v3-coordination"}' >/dev/null 2>&1 || true

# Record baseline state
BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[].name] // []' 2>/dev/null || echo '[]')
BASELINE_CHANNELS=$(rc_api GET "channels.list?count=200" | jq '[.channels[].name] // []' 2>/dev/null || echo '[]')

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "frontend_channel_id": "${FRONTEND_ID:-}",
  "backend_channel_id": "${BACKEND_ID:-}",
  "payments_channel_id": "${PAYMENTS_ID:-}",
  "infra_channel_id": "${INFRA_ID:-}",
  "announcements_channel_id": "${ANNOUNCE_ID:-}",
  "frontend_checklist_msg_id": "${FRONTEND_CHECKLIST_MSG_ID:-}",
  "backend_checklist_msg_id": "${BACKEND_CHECKLIST_MSG_ID:-}",
  "payments_checklist_msg_id": "${PAYMENTS_CHECKLIST_MSG_ID:-}",
  "infra_checklist_msg_id": "${INFRA_CHECKLIST_MSG_ID:-}",
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
echo "Frontend channel ID: ${FRONTEND_ID:-unknown}"
echo "Backend channel ID: ${BACKEND_ID:-unknown}"
echo "Payments channel ID: ${PAYMENTS_ID:-unknown}"
echo "Infra channel ID: ${INFRA_ID:-unknown}"
echo "Announcements channel ID: ${ANNOUNCE_ID:-unknown}"
echo "Frontend checklist msg ID: ${FRONTEND_CHECKLIST_MSG_ID:-unknown}"
echo "Backend checklist msg ID: ${BACKEND_CHECKLIST_MSG_ID:-unknown}"
echo "Payments checklist msg ID: ${PAYMENTS_CHECKLIST_MSG_ID:-unknown}"
echo "Infra checklist msg ID: ${INFRA_CHECKLIST_MSG_ID:-unknown}"
