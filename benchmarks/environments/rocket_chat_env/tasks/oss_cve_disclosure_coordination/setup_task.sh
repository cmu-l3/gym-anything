#!/bin/bash
set -euo pipefail

echo "=== Setting up oss_cve_disclosure_coordination task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="oss_cve_disclosure_coordination"

rm -f "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_start_ts" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_baseline.json" 2>/dev/null || true

if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

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

create_user_if_not_exists() {
  local username="$1"
  local name="$2"
  local email="$3"
  rc_api POST "users.create" \
    "{\"username\":\"${username}\",\"name\":\"${name}\",\"email\":\"${email}\",\"password\":\"UserPass123!\",\"verified\":true,\"roles\":[\"user\"],\"joinDefaultChannels\":false,\"requirePasswordChange\":false,\"sendWelcomeEmail\":false}" >/dev/null 2>&1 || true
  echo "Ensured user: $username"
}

# Create relevant users
create_user_if_not_exists "security.researcher" "Alex Chen (External Researcher)" "alex.chen@bugbounty.example.com"
create_user_if_not_exists "core.maintainer" "Fatima Hassan - Core Maintainer" "fatima@openinfra-foundation.org"
create_user_if_not_exists "release.manager" "Jonas Weber - Release Manager" "jonas@openinfra-foundation.org"
create_user_if_not_exists "lib.author" "Deepa Nair - Original Library Author" "deepa@openinfra-foundation.org"
create_user_if_not_exists "enterprise.consumer" "TechFlow Security Team" "security@techflow-enterprise.com"
create_user_if_not_exists "cloud.vendor" "CloudScale Infra Security" "security@cloudscale-vendor.com"
create_user_if_not_exists "distro.maintainer" "Lena Vogt - OpenDistro Maintainer" "lena@opendistro-linux.org"
create_user_if_not_exists "foundation.counsel" "Legal Counsel - Foundation" "legal@openinfra-foundation.org"
create_user_if_not_exists "security.lead.internal" "Marcos Silva - Internal Security Lead" "marcos@openinfra-foundation.org"

# Clean up any pre-existing disclosure coordination channels
for ch in "cve-coordination" "cve-2026" "disclosure-embargo" "patch-review" "security-embargo" "vuln-disclosure"; do
  rc_api POST "groups.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
  rc_api POST "channels.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
done

# Create #security-triage (existing internal channel where initial report came in)
TRIAGE_RESP=$(rc_api POST "channels.create" \
  '{"name":"security-triage","members":["core.maintainer","release.manager","lib.author","security.lead.internal","foundation.counsel"],"readOnly":false}')
TRIAGE_ID=$(echo "$TRIAGE_RESP" | jq -r '.channel._id // empty')
if [ -z "$TRIAGE_ID" ]; then
  TRIAGE_INFO=$(rc_api GET "channels.info?roomName=security-triage")
  TRIAGE_ID=$(echo "$TRIAGE_INFO" | jq -r '.channel._id // empty')
fi

TRIAGE_MSG1_ID=""
TRIAGE_MSG2_ID=""

if [ -n "$TRIAGE_ID" ]; then
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#security-triage","text":"[Incoming] HackerOne report submitted 2026-03-05 by researcher \"acuteangle\" (verified): Heap buffer overflow in libparse v2.x deserialization path. Triggered by malformed YAML input. PoC demonstrates reliable code execution on affected versions 2.0.0-2.14.3. Researcher requesting acknowledgment within 24h per our disclosure policy."}' >/dev/null

  sleep 0.3
  TRIAGE_MSG1_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#security-triage","text":"Initial triage complete. @core.maintainer @lib.author — the vulnerable codepath is in src/deserialize/yaml_parser.c lines 847-923. The heap overflow occurs when field length exceeds buffer allocation in parse_nested_map(). CVSS v3.1 base score: 9.8 (Critical). @release.manager — affected versions: libparse 2.0.0 through 2.14.3. v1.x branch is NOT affected. Patch coordination must be private. Known downstream dependents at risk: TechFlow Enterprise Platform, CloudScale infrastructure-as-code tooling, OpenDistro package ecosystem (700+ packages). @admin we need coordinated disclosure — suggest 7-day embargo with simultaneous patch release."}')
  TRIAGE_MSG1_ID=$(echo "$TRIAGE_MSG1_RESP" | jq -r '.message._id // empty')

  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#security-triage","text":"@foundation.counsel please review. Researcher has agreed to standard 90-day responsible disclosure, but given critical severity they are flexible on timeline if we can ship patch within 7 days. We need to notify downstream consumers under embargo BEFORE any public disclosure. NDA/embargo terms in our policy doc apply. @admin please coordinate."}' >/dev/null

  sleep 0.3
  TRIAGE_MSG2_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#security-triage","text":"@release.manager — patch branch `security/heap-overflow-fix-2026-03` is in progress. @core.maintainer reviewing. Do NOT merge to main or tag until embargo coordination complete. Estimated patch ready: 2026-03-10. Proposed public disclosure: 2026-03-12 14:00 UTC. Need: (1) private patch review session with maintainers, (2) embargo notifications to TechFlow/CloudScale/OpenDistro, (3) confirmation from researcher on timeline, (4) draft advisory for CVE assignment. @admin this all needs to happen in the next 4 days."}')
  TRIAGE_MSG2_ID=$(echo "$TRIAGE_MSG2_RESP" | jq -r '.message._id // empty')
fi

# Create #foundation-security-general for broader context
FSG_RESP=$(rc_api POST "channels.create" \
  '{"name":"foundation-security-general","members":["core.maintainer","release.manager","lib.author","security.lead.internal","foundation.counsel"],"readOnly":false}')
FSG_ID=$(echo "$FSG_RESP" | jq -r '.channel._id // empty')
if [ -z "$FSG_ID" ]; then
  FSG_INFO=$(rc_api GET "channels.info?roomName=foundation-security-general")
  FSG_ID=$(echo "$FSG_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$FSG_ID" ]; then
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#foundation-security-general","text":"Reminder: our security disclosure policy (sec-policy-v3.pdf) requires:\n- Private notification to known major downstream consumers at least 72h before public disclosure\n- CVE ID requested via MITRE or GitHub Advisory Database before disclosure\n- Researcher credited in advisory (if they consent)\n- Simultaneous patch release with advisory publication\n- All coordination must happen in private channels (not public)"}' >/dev/null
fi

# Record baseline state
BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[].name] // []' 2>/dev/null || echo '[]')

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "triage_channel_id": "${TRIAGE_ID:-}",
  "triage_msg1_id": "${TRIAGE_MSG1_ID:-}",
  "triage_msg2_id": "${TRIAGE_MSG2_ID:-}",
  "baseline_groups": ${BASELINE_GROUPS}
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

echo "=== Setup complete ==="
echo "Triage message IDs: ${TRIAGE_MSG1_ID:-none}, ${TRIAGE_MSG2_ID:-none}"
