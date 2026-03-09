#!/bin/bash
set -euo pipefail

echo "=== Setting up vendor_security_audit_escalation task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="vendor_security_audit_escalation"

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

create_user_if_not_exists "ciso" "Chief Information Security Officer" "ciso@company.local"
create_user_if_not_exists "security.analyst" "Security Analyst" "security.analyst@company.local"
create_user_if_not_exists "vendor.liaison" "Vendor Liaison Manager" "vendor.liaison@company.local"
create_user_if_not_exists "compliance.officer" "Compliance Officer" "compliance.officer@company.local"
create_user_if_not_exists "devops.lead" "DevOps Lead" "devops.lead@company.local"
create_user_if_not_exists "network.admin" "Network Administrator" "network.admin@company.local"

# Create #security-alerts channel and seed alert messages
ALERTS_RESP=$(rc_api POST "channels.create" \
  '{"name":"security-alerts","members":["ciso","security.analyst","vendor.liaison","compliance.officer","devops.lead","network.admin"],"readOnly":false}')
ALERTS_ID=$(echo "$ALERTS_RESP" | jq -r '.channel._id // empty')

if [ -z "$ALERTS_ID" ]; then
  ALERTS_INFO=$(rc_api GET "channels.info?roomName=security-alerts")
  ALERTS_ID=$(echo "$ALERTS_INFO" | jq -r '.channel._id // empty')
fi

# Seed realistic security alert messages
PENTEST_ALERT_MSG_ID=""
if [ -n "$ALERTS_ID" ]; then
  rc_api POST "chat.postMessage" \
    '{"channel":"#security-alerts","text":"[INFO] Monthly vulnerability scan completed. 12 low-severity findings identified across development environments. No production impact. Full report: /shared/security/vuln-scan-feb-2026.pdf"}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#security-alerts","text":"[WARNING] Unusual login pattern detected for service account svc-etl-prod. 47 failed attempts from IP 10.42.8.19 between 02:00-04:00 UTC. Account locked per policy. Investigating potential credential stuffing."}' >/dev/null
  sleep 0.3

  PENTEST_ALERT_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#security-alerts","text":"[CRITICAL] Third-party penetration test by CyberGuard Solutions completed. 3 critical vulnerabilities identified: CVE-2026-0142 (CVSS 9.8, SQL injection in PayStream API), CVE-2026-0198 (CVSS 9.1, Auth bypass in IdentityBridge SSO), CVE-2026-0215 (CVSS 8.6, Insecure deserialization in DataSync). Immediate remediation required per PCI-DSS compliance. Full report: /shared/security/pentest-2026-Q1.pdf"}')
  PENTEST_ALERT_MSG_ID=$(echo "$PENTEST_ALERT_RESP" | jq -r '.message._id // empty')
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#security-alerts","text":"[INFO] Firewall rule update applied to edge routers ER-01 through ER-04. New rules block traffic from 23 additional known-malicious IP ranges. Change ticket: SEC-2891."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#security-alerts","text":"[WARNING] TLS 1.0 connections still observed from legacy client integration partner DataFlow Inc. 142 connections in last 24 hours. Deprecation deadline: 2026-03-31. Escalation ticket: SEC-2903."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#security-alerts","text":"[INFO] Annual SOC 2 audit scheduled for 2026-03-20. Pre-audit documentation review meeting set for 2026-03-12. All control owners notified."}' >/dev/null
fi

# Create #vendor-integrations channel with some discussion
rc_api POST "channels.create" \
  '{"name":"vendor-integrations","members":["vendor.liaison","devops.lead","security.analyst","compliance.officer"],"readOnly":false}' >/dev/null 2>&1 || true

VENDOR_CH_INFO=$(rc_api GET "channels.info?roomName=vendor-integrations")
VENDOR_CH_ID=$(echo "$VENDOR_CH_INFO" | jq -r '.channel._id // empty')

if [ -n "$VENDOR_CH_ID" ]; then
  rc_api POST "chat.postMessage" \
    '{"channel":"#vendor-integrations","text":"PayStream API v3.2 migration is on track for Q2. Their team confirmed backward compatibility with our existing payment flows. Documentation review scheduled for next week."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#vendor-integrations","text":"IdentityBridge SSO connector renewal contract signed. New SLA includes 99.95% uptime guarantee and 4-hour critical patch response time."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#vendor-integrations","text":"DataSync middleware v2.1 hotfix deployed to staging. Performance benchmarks show 15% improvement in batch processing throughput. Production rollout pending QA sign-off."}' >/dev/null
fi

# Delete any pre-existing remediation channel to ensure clean state
rc_api POST "groups.delete" '{"roomName":"sec-remediation-2026-03-06"}' >/dev/null 2>&1 || true
rc_api POST "channels.delete" '{"roomName":"sec-remediation-2026-03-06"}' >/dev/null 2>&1 || true

# Record baseline state
BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[].name] // []' 2>/dev/null || echo '[]')
BASELINE_CHANNELS=$(rc_api GET "channels.list?count=200" | jq '[.channels[].name] // []' 2>/dev/null || echo '[]')

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "pentest_alert_msg_id": "${PENTEST_ALERT_MSG_ID:-}",
  "security_alerts_id": "${ALERTS_ID:-}",
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
echo "Pentest alert message ID: ${PENTEST_ALERT_MSG_ID:-unknown}"
echo "Security alerts channel ID: ${ALERTS_ID:-unknown}"
