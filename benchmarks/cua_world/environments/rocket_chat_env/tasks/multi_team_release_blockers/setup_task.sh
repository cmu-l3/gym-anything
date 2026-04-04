#!/bin/bash
set -euo pipefail

echo "=== Setting up multi_team_release_blockers task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="multi_team_release_blockers"

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

# Create team members
create_user_if_not_exists "backend.lead" "Yusuf Adeyemi - Backend Lead" "yusuf.a@devco.io"
create_user_if_not_exists "security.eng" "Hana Kovacs - Security Engineer" "hana.k@devco.io"
create_user_if_not_exists "qa.lead" "Raj Patel - QA Lead" "raj.p@devco.io"
create_user_if_not_exists "vp.engineering" "Sandra Muller - VP Engineering" "sandra.m@devco.io"
create_user_if_not_exists "product.manager" "Leo Tanaka - Product Manager" "leo.t@devco.io"
create_user_if_not_exists "sales.lead" "Camille Dubois - Sales Lead" "camille.d@devco.io"
create_user_if_not_exists "devops.lead" "Arjun Singh - DevOps Lead" "arjun.s@devco.io"
create_user_if_not_exists "frontend.dev2" "Mei Lin - Frontend Developer" "mei.l@devco.io"

# Clean up any pre-existing coordination channels
for ch in "v4-release-blocker" "release-v4" "go-no-go" "release-coordination" "v4-go-nogo"; do
  rc_api POST "groups.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
  rc_api POST "channels.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
done

# Create #release-v4 channel (existing release coordination channel)
RV4_RESP=$(rc_api POST "channels.create" \
  '{"name":"release-v4","members":["backend.lead","security.eng","qa.lead","vp.engineering","product.manager","sales.lead","devops.lead","frontend.dev2"],"readOnly":false}')
RV4_ID=$(echo "$RV4_RESP" | jq -r '.channel._id // empty')
if [ -z "$RV4_ID" ]; then
  RV4_INFO=$(rc_api GET "channels.info?roomName=release-v4")
  RV4_ID=$(echo "$RV4_INFO" | jq -r '.channel._id // empty')
fi

RV4_MSG1_ID=""
RV4_MSG2_ID=""
RV4_MSG3_ID=""

if [ -n "$RV4_ID" ]; then
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#release-v4","text":"@channel — v4.0 was supposed to go out yesterday (March 6). We have three open issues being called blockers by their respective teams but no consensus on what is actually go/no-go. @backend.lead @security.eng @qa.lead each of you has flagged something. @admin can you call this? We need a decision in the next few hours. Sales is already fielding customer questions."}' >/dev/null

  sleep 0.3
  RV4_MSG1_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#release-v4","text":"Backend blocker (reported by @backend.lead): Migration script v4_schema_migration_047 fails on tables with > 5M rows in production DBs. Our staging DB only has 800K rows so we missed this in testing. Affects 3 of our 12 enterprise customers. Workaround: run migration in batches (script exists, needs 30min manual intervention per affected customer). Fix ETA: backend says 2 days for automated solution. @backend.lead says this is a go/no-go blocker. @devops.lead disagrees — says workaround is acceptable."}')
  RV4_MSG1_ID=$(echo "$RV4_MSG1_RESP" | jq -r '.message._id // empty')

  sleep 0.3
  RV4_MSG2_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#release-v4","text":"Security blocker (reported by @security.eng): Static analysis scan (Semgrep) flagged 2 findings in the new OAuth2 PKCE implementation — one high severity (potential CSRF in token refresh flow), one medium (verbose error messages leaking internal paths). @security.eng says both must be fixed before release. @backend.lead reviewed the high severity and says the CSRF vector is theoretical given our CORS config, not exploitable in practice. They disagree on whether this is a genuine blocker. Security scan report is in #engineering-security channel. @admin needs to make the call."}')
  RV4_MSG2_ID=$(echo "$RV4_MSG2_RESP" | jq -r '.message._id // empty')

  sleep 0.3
  RV4_MSG3_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#release-v4","text":"QA blocker (reported by @qa.lead): 3 end-to-end tests are failing on the payment flow in the staging environment. @qa.lead filed these as release blockers. @devops.lead traced them to a staging environment config drift (wrong Stripe test key in CI). The tests PASS locally and in the dedicated QA environment. @qa.lead wants all e2e tests green before signing off. @devops.lead says this is a staging infra issue, not a v4.0 code issue. They have been arguing about this since yesterday. @admin — we need a ruling."}')
  RV4_MSG3_ID=$(echo "$RV4_MSG3_RESP" | jq -r '.message._id // empty')

  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#release-v4","text":"@vp.engineering @product.manager — sales committed v4.0 to three enterprise customers for the week of March 3. @sales.lead has been getting inbound calls. Every day of delay costs us credibility. Someone please make a decision on these three blockers. @admin is that you?"}' >/dev/null
fi

# Create #engineering-security for the security scan context
SEC_RESP=$(rc_api POST "channels.create" \
  '{"name":"engineering-security","members":["security.eng","backend.lead","vp.engineering","devops.lead"],"readOnly":false}')
SEC_ID=$(echo "$SEC_RESP" | jq -r '.channel._id // empty')
if [ -z "$SEC_ID" ]; then
  SEC_INFO=$(rc_api GET "channels.info?roomName=engineering-security")
  SEC_ID=$(echo "$SEC_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$SEC_ID" ]; then
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#engineering-security","text":"Semgrep scan v4.0-rc3 results summary: 1 HIGH (oauth2_pkce.py line 247 — state parameter not validated against session in token refresh handler), 1 MEDIUM (api_error_handler.py line 89 — stack trace included in 500 response body in non-production mode flag not enforced). Both findings are in new v4.0 code, not regressions from v3.x. @security.eng owns the final sign-off decision."}' >/dev/null
fi

# Create #backend-team for additional context
BT_RESP=$(rc_api POST "channels.create" \
  '{"name":"backend-team","members":["backend.lead","devops.lead","vp.engineering"],"readOnly":false}')
BT_ID=$(echo "$BT_RESP" | jq -r '.channel._id // empty')
if [ -z "$BT_ID" ]; then
  BT_INFO=$(rc_api GET "channels.info?roomName=backend-team")
  BT_ID=$(echo "$BT_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$BT_ID" ]; then
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#backend-team","text":"@backend.lead the migration batch script (scripts/migrate_large_tables.sh) is tested and works. If we get sign-off to ship v4.0 now with the manual workaround, DevOps can run it for the 3 affected customers in about 2 hours total. Not ideal but doable for the release. The 2-day fix is for making it fully automated for future releases. This is your call to make."}' >/dev/null
fi

# Record baseline state
BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[].name] // []' 2>/dev/null || echo '[]')

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "rv4_channel_id": "${RV4_ID:-}",
  "rv4_msg1_id": "${RV4_MSG1_ID:-}",
  "rv4_msg2_id": "${RV4_MSG2_ID:-}",
  "rv4_msg3_id": "${RV4_MSG3_ID:-}",
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
echo "Release channel v4 msg IDs: ${RV4_MSG1_ID:-none}, ${RV4_MSG2_ID:-none}, ${RV4_MSG3_ID:-none}"
