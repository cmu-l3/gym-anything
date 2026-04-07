#!/bin/bash
set -euo pipefail

echo "=== Setting up platform_migration_cutover_coordination task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="platform_migration_cutover_coordination"

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

# Helper: post message with username prefix in text (no alias permission needed)
post_as() {
  local channel="$1"
  local user="$2"
  local text="$3"
  sleep 1
  rc_api POST "chat.postMessage" \
    "{\"channel\":\"${channel}\",\"text\":\"[${user}]: ${text}\"}"
}

create_user_if_not_exists() {
  local username="$1"
  local name="$2"
  local email="$3"
  rc_api POST "users.create" \
    "{\"username\":\"${username}\",\"name\":\"${name}\",\"email\":\"${email}\",\"password\":\"UserPass123!\",\"verified\":true,\"roles\":[\"user\"],\"joinDefaultChannels\":false,\"requirePasswordChange\":false,\"sendWelcomeEmail\":false}" >/dev/null 2>&1 || true
  echo "Ensured user: $username"
}

# =========================================================================
# CREATE USERS (10 users)
# =========================================================================
create_user_if_not_exists "db.lead"          "Anika Sharma - Database Lead"      "anika.sharma@atlas.io"
create_user_if_not_exists "network.lead"     "Tomas Herrera - Networking Lead"   "tomas.herrera@atlas.io"
create_user_if_not_exists "backend.lead"     "Priya Okonkwo - Backend Lead"      "priya.okonkwo@atlas.io"
create_user_if_not_exists "frontend.lead"    "Marcus Wei - Frontend Lead"        "marcus.wei@atlas.io"
create_user_if_not_exists "qa.lead"          "Elena Rossi - QA Lead"             "elena.rossi@atlas.io"
create_user_if_not_exists "sre.oncall"       "Derek Oduya - SRE On-Call"         "derek.oduya@atlas.io"
create_user_if_not_exists "cloud.architect"  "Sana Abbasi - Cloud Architect"     "sana.abbasi@atlas.io"
create_user_if_not_exists "vp.engineering"   "James Lindqvist - VP Engineering"  "james.lindqvist@atlas.io"
create_user_if_not_exists "security.lead"    "Nadia Kovalenko - Security Lead"   "nadia.kovalenko@atlas.io"
create_user_if_not_exists "product.owner"    "Kenji Mori - Product Owner"        "kenji.mori@atlas.io"

# =========================================================================
# CLEANUP: Delete pre-existing war room channel (ensure clean slate)
# =========================================================================
for ch in "atlas-cutover-war-room" "atlas-war-room" "cutover-war-room" "atlas-cutover"; do
  rc_api POST "groups.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
  rc_api POST "channels.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
done

# =========================================================================
# CHANNEL 1: #atlas-database (3 messages)
# =========================================================================
DB_RESP=$(rc_api POST "channels.create" \
  '{"name":"atlas-database","members":["db.lead","qa.lead","cloud.architect"],"readOnly":false}')
DB_ID=$(echo "$DB_RESP" | jq -r '.channel._id // empty')
if [ -z "$DB_ID" ]; then
  DB_INFO=$(rc_api GET "channels.info?roomName=atlas-database")
  DB_ID=$(echo "$DB_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$DB_ID" ]; then
  post_as "#atlas-database" "db.lead" "Pre-cutover status: GO. MongoDB replica set migration dry-run completed successfully. 847GB data, estimated transfer time: 2h15m. Checksums verified across all collections. Failback procedure tested -- can restore from point-in-time backup within 40 minutes. One note: the cloud MongoDB instance connection pooling is configured for max 200 connections; our peak observed is 185. Recommend bumping to 300 before cutover." >/dev/null
  post_as "#atlas-database" "cloud.architect" "Connection pool bump to 300 submitted as change request CR-4421. Will be applied during pre-cutover window at 00:30 UTC." >/dev/null
  post_as "#atlas-database" "db.lead" "CR-4421 confirmed. All database pre-cutover items GREEN. Final backup snapshot scheduled for 00:45 UTC." >/dev/null
fi

# =========================================================================
# CHANNEL 2: #atlas-networking (6 messages)
# =========================================================================
NET_RESP=$(rc_api POST "channels.create" \
  '{"name":"atlas-networking","members":["network.lead","security.lead","cloud.architect"],"readOnly":false}')
NET_ID=$(echo "$NET_RESP" | jq -r '.channel._id // empty')
if [ -z "$NET_ID" ]; then
  NET_INFO=$(rc_api GET "channels.info?roomName=atlas-networking")
  NET_ID=$(echo "$NET_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$NET_ID" ]; then
  post_as "#atlas-networking" "network.lead" "Pre-cutover status: CONDITIONAL. DNS propagation tests passed for all 12 endpoints. BGP failover tested OK. However, the TLS certificate for api.atlas-cloud.internal expires 2026-03-19 -- just 24 hours after cutover window ends. If cutover extends or we need to rollback and re-cutover, we will be operating on an expired cert. Requesting emergency cert renewal before cutover." >/dev/null
  post_as "#atlas-networking" "security.lead" "Emergency cert renewal requires approval from security-compliance. I have submitted the request (CERT-2026-0312) but compliance team reviews are batched and the next review window is Tuesday 2026-03-19." >/dev/null
  post_as "#atlas-networking" "network.lead" "Can we get an expedited review? We cannot proceed to full GO without this resolved. If the cert expires during a rollback scenario, all API traffic through the cloud gateway will fail TLS validation." >/dev/null
  post_as "#atlas-networking" "cloud.architect" "I will escalate CERT-2026-0312. Worst case, we could add a temporary cert exception in the gateway config, but that is a security risk I would rather not take." >/dev/null
  post_as "#atlas-networking" "network.lead" "UPDATE: CERT-2026-0312 expedited approval granted. New cert deployed to api.atlas-cloud.internal, expiry now 2027-03-18. However, during cert deployment I noticed the cloud API gateway TLS termination is configured for TLS 1.2 only. Our cloud API endpoints require TLS 1.3 minimum per the security baseline. Patching gateway config now, ETA 30 minutes." >/dev/null
  post_as "#atlas-networking" "network.lead" "TLS 1.3 patch applied to gateway staging. Production patch requires a 2-minute gateway restart during the maintenance window. Adding to cutover runbook as a pre-migration step. Status remains: CONDITIONAL pending production gateway restart confirmation at cutover time." >/dev/null
fi

# =========================================================================
# CHANNEL 3: #atlas-backend (3 messages)
# =========================================================================
BE_RESP=$(rc_api POST "channels.create" \
  '{"name":"atlas-backend","members":["backend.lead","qa.lead","cloud.architect"],"readOnly":false}')
BE_ID=$(echo "$BE_RESP" | jq -r '.channel._id // empty')
if [ -z "$BE_ID" ]; then
  BE_INFO=$(rc_api GET "channels.info?roomName=atlas-backend")
  BE_ID=$(echo "$BE_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$BE_ID" ]; then
  post_as "#atlas-backend" "backend.lead" "Pre-cutover status: GO. All 14 microservices pass health checks against cloud staging environment. Connection string switchover tested in canary deployment -- latency within 3ms of on-prem baseline. Feature flag atlas-cloud-routing tested in shadow mode for 72 hours, zero errors. Ready to flip at cutover." >/dev/null
  post_as "#atlas-backend" "backend.lead" "One dependency note: Payment Processing Service (PPS) has a hardcoded on-prem database connection string in its config map. We need to update this as part of the database migration step, BEFORE enabling cloud routing for PPS. Adding to runbook as a sequencing constraint: DB migration must complete, then PPS config update, then backend cloud routing." >/dev/null
  post_as "#atlas-backend" "qa.lead" "Confirmed -- PPS config dependency is documented in the integration test suite. Test ID: INT-PPS-CLOUD-001. We will run this immediately after db migration step completes to validate PPS connectivity before proceeding." >/dev/null
fi

# =========================================================================
# CHANNEL 4: #atlas-frontend (3 messages)
# =========================================================================
FE_RESP=$(rc_api POST "channels.create" \
  '{"name":"atlas-frontend","members":["frontend.lead","qa.lead"],"readOnly":false}')
FE_ID=$(echo "$FE_RESP" | jq -r '.channel._id // empty')
if [ -z "$FE_ID" ]; then
  FE_INFO=$(rc_api GET "channels.info?roomName=atlas-frontend")
  FE_ID=$(echo "$FE_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$FE_ID" ]; then
  post_as "#atlas-frontend" "frontend.lead" "Pre-cutover status: GO. CDN cache invalidation script tested. Asset rewrite rules verified for cloud endpoints. WebSocket reconnection logic handles the expected 30-second connection drop during DNS switch gracefully." >/dev/null
  post_as "#atlas-frontend" "frontend.lead" "Note: We will need a 2-minute UI maintenance banner displayed before the DNS switch. I have prepared the banner configuration but need admin to enable it via the feature flag maintenance-banner-atlas at cutover time." >/dev/null
  post_as "#atlas-frontend" "qa.lead" "Frontend smoke tests pass against cloud staging. Mobile responsiveness OK. One flaky test (FE-SMOKE-047: WebSocket heartbeat timeout) but manual verification confirms it works. Marking as known flake, not a blocker." >/dev/null
fi

# =========================================================================
# CHANNEL 5: #atlas-qa (3 messages)
# =========================================================================
QA_RESP=$(rc_api POST "channels.create" \
  '{"name":"atlas-qa","members":["qa.lead","sre.oncall","cloud.architect"],"readOnly":false}')
QA_ID=$(echo "$QA_RESP" | jq -r '.channel._id // empty')
if [ -z "$QA_ID" ]; then
  QA_INFO=$(rc_api GET "channels.info?roomName=atlas-qa")
  QA_ID=$(echo "$QA_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$QA_ID" ]; then
  post_as "#atlas-qa" "qa.lead" "Cutover validation plan finalized. 3 phases: Phase 1 (post-db-migration): data integrity checks, PPS connection verification via INT-PPS-CLOUD-001. Phase 2 (post-backend-cutover): API endpoint smoke tests, latency benchmarks against on-prem baseline. Phase 3 (post-frontend-cutover): E2E user journey tests, CDN verification. Total estimated validation time: 45 minutes." >/dev/null
  post_as "#atlas-qa" "qa.lead" "Rollback criteria: Any Phase 1 failure triggers immediate rollback. Phase 2 failure triggers rollback if not resolved within 15 minutes. Phase 3 failure is case-by-case assessment with Migration Lead." >/dev/null
  post_as "#atlas-qa" "sre.oncall" "Monitoring dashboards for cutover are live. Alert thresholds set: error rate greater than 1 percent, p99 latency greater than 800ms, database connection failures greater than 5 per minute. PagerDuty escalation policy confirmed for Atlas migration." >/dev/null
fi

# =========================================================================
# CHANNEL 6: #ops-alerts (2 alert messages -- IDs saved for thread verification)
# =========================================================================
OPS_RESP=$(rc_api POST "channels.create" \
  '{"name":"ops-alerts","members":["sre.oncall","db.lead","network.lead","backend.lead"],"readOnly":false}')
OPS_ID=$(echo "$OPS_RESP" | jq -r '.channel._id // empty')
if [ -z "$OPS_ID" ]; then
  OPS_INFO=$(rc_api GET "channels.info?roomName=ops-alerts")
  OPS_ID=$(echo "$OPS_INFO" | jq -r '.channel._id // empty')
fi

ALERT1_MSG_ID=""
ALERT2_MSG_ID=""

if [ -n "$OPS_ID" ]; then
  sleep 1
  ALERT1_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#ops-alerts","text":"[sre.oncall]: [ALERT] Pre-cutover health check WARN: Cloud load balancer atlas-lb-prod-01 showing intermittent 502 responses (3 in last hour). Source: synthetic monitoring probe. Not blocking, but monitoring closely."}')
  ALERT1_MSG_ID=$(echo "$ALERT1_RESP" | jq -r '.message._id // empty')

  sleep 1
  ALERT2_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#ops-alerts","text":"[sre.oncall]: [ALERT] Pre-cutover health check CRITICAL: On-prem backup job for payment-db-prod failed at 22:15 UTC with error: Disk quota exceeded on backup volume /mnt/backup-san-07. Last successful backup: 2026-03-17 18:00 UTC. Immediate attention required -- this backup is a prerequisite for cutover rollback safety."}')
  ALERT2_MSG_ID=$(echo "$ALERT2_RESP" | jq -r '.message._id // empty')
fi

# =========================================================================
# CHANNEL 7: #engineering-announcements (2 historical messages)
# =========================================================================
ANN_RESP=$(rc_api POST "channels.create" \
  '{"name":"engineering-announcements","members":["vp.engineering","product.owner","db.lead","network.lead","backend.lead","frontend.lead","qa.lead","sre.oncall","cloud.architect","security.lead"],"readOnly":false}')
ANN_ID=$(echo "$ANN_RESP" | jq -r '.channel._id // empty')
if [ -z "$ANN_ID" ]; then
  ANN_INFO=$(rc_api GET "channels.info?roomName=engineering-announcements")
  ANN_ID=$(echo "$ANN_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$ANN_ID" ]; then
  post_as "#engineering-announcements" "vp.engineering" "Project Atlas: Cloud Migration Timeline Update -- Cutover now confirmed for maintenance window 2026-03-18 01:00-05:00 UTC. All team leads: post your final readiness status in your atlas-* channels by EOD Friday. Migration Lead will coordinate go/no-go." >/dev/null
  post_as "#engineering-announcements" "product.owner" "Customer communication plan for Atlas cutover: Status page pre-updated with scheduled maintenance notice. Support team briefed on escalation path. Rollback communication template prepared. Marketing approved the zero-downtime migration messaging contingent on successful cutover." >/dev/null
fi

# =========================================================================
# RECORD BASELINE STATE
# =========================================================================
BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[].name] // []' 2>/dev/null || echo '[]')
BASELINE_CHANNELS=$(rc_api GET "channels.list?count=200" | jq '[.channels[].name] // []' 2>/dev/null || echo '[]')

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "ops_channel_id": "${OPS_ID:-}",
  "alert1_msg_id": "${ALERT1_MSG_ID:-}",
  "alert2_msg_id": "${ALERT2_MSG_ID:-}",
  "announcements_channel_id": "${ANN_ID:-}",
  "baseline_groups": ${BASELINE_GROUPS},
  "baseline_channels": ${BASELINE_CHANNELS}
}
EOF

date +%s > "/tmp/${TASK_NAME}_start_ts"

# =========================================================================
# LAUNCH BROWSER
# =========================================================================
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

take_screenshot "/tmp/${TASK_NAME}_start.png"

echo "=== Setup complete ==="
echo "Ops channel ID: ${OPS_ID:-unknown}"
echo "Alert 1 msg ID: ${ALERT1_MSG_ID:-unknown}"
echo "Alert 2 msg ID: ${ALERT2_MSG_ID:-unknown}"
echo "Announcements channel ID: ${ANN_ID:-unknown}"
