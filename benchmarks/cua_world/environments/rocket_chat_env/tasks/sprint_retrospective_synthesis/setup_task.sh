#!/bin/bash
set -euo pipefail

echo "=== Setting up sprint_retrospective_synthesis task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="sprint_retrospective_synthesis"

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

create_user_if_not_exists "eng.director" "Engineering Director" "eng.director@company.local"
create_user_if_not_exists "alpha.lead" "Alpha Team Lead" "alpha.lead@company.local"
create_user_if_not_exists "beta.lead" "Beta Team Lead" "beta.lead@company.local"
create_user_if_not_exists "gamma.lead" "Gamma Team Lead" "gamma.lead@company.local"
create_user_if_not_exists "product.manager" "Product Manager" "product.manager@company.local"
create_user_if_not_exists "ux.researcher" "UX Researcher" "ux.researcher@company.local"

# Create #retro-team-alpha channel and seed retrospective messages
ALPHA_RESP=$(rc_api POST "channels.create" \
  '{"name":"retro-team-alpha","members":["alpha.lead","eng.director"],"readOnly":false}')
ALPHA_ID=$(echo "$ALPHA_RESP" | jq -r '.channel._id // empty')

if [ -z "$ALPHA_ID" ]; then
  ALPHA_INFO=$(rc_api GET "channels.info?roomName=retro-team-alpha")
  ALPHA_ID=$(echo "$ALPHA_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$ALPHA_ID" ]; then
  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-alpha","text":"What went well: Our new CI/CD pipeline reduced deployment time from 45 minutes to 12 minutes. Great work by the platform team."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-alpha","text":"What didn'\''t go well: Code review turnaround time averaged 3 days this sprint. We need to establish SLA for reviews."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-alpha","text":"What went well: Customer-reported bugs dropped 40% after we introduced the automated regression suite."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-alpha","text":"Action needed: We should adopt trunk-based development to reduce merge conflicts. Lost 2 days to a merge hell on the billing feature."}' >/dev/null
fi

# Create #retro-team-beta channel and seed retrospective messages
BETA_RESP=$(rc_api POST "channels.create" \
  '{"name":"retro-team-beta","members":["beta.lead","eng.director","product.manager"],"readOnly":false}')
BETA_ID=$(echo "$BETA_RESP" | jq -r '.channel._id // empty')

if [ -z "$BETA_ID" ]; then
  BETA_INFO=$(rc_api GET "channels.info?roomName=retro-team-beta")
  BETA_ID=$(echo "$BETA_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$BETA_ID" ]; then
  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-beta","text":"What went well: Successfully shipped the real-time analytics dashboard 2 days ahead of schedule."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-beta","text":"What didn'\''t go well: Handoff between design and engineering is still painful. Specs were incomplete for 3 out of 5 stories."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-beta","text":"What didn'\''t go well: On-call rotation was exhausting - we had 47 alerts this sprint, 80% were false positives. Alert fatigue is real."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-beta","text":"Action needed: Need better monitoring thresholds. Current alerts are too sensitive and causing burnout."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-beta","text":"What went well: Pair programming sessions improved knowledge sharing. New team members ramped up faster."}' >/dev/null
fi

# Create #retro-team-gamma channel and seed retrospective messages
GAMMA_RESP=$(rc_api POST "channels.create" \
  '{"name":"retro-team-gamma","members":["gamma.lead","eng.director","ux.researcher"],"readOnly":false}')
GAMMA_ID=$(echo "$GAMMA_RESP" | jq -r '.channel._id // empty')

if [ -z "$GAMMA_ID" ]; then
  GAMMA_INFO=$(rc_api GET "channels.info?roomName=retro-team-gamma")
  GAMMA_ID=$(echo "$GAMMA_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$GAMMA_ID" ]; then
  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-gamma","text":"What went well: API response times improved by 35% after the database indexing optimization."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-gamma","text":"What didn'\''t go well: Cross-team dependencies blocked us for 5 days. No clear escalation path when Team Alpha'\''s API changes broke our integration."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-gamma","text":"What didn'\''t go well: Code review turnaround is a problem here too - averaged 2.5 days. Aligns with what Alpha reported."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-gamma","text":"Action needed: Establish a cross-team dependency management process and shared API contract testing."}' >/dev/null
  sleep 0.3

  rc_api POST "chat.postMessage" \
    '{"channel":"#retro-team-gamma","text":"What went well: User research sessions led to 3 UX improvements that increased conversion by 12%."}' >/dev/null
fi

# Delete any pre-existing q1-retro-action-items channel to ensure clean state
rc_api POST "channels.delete" '{"roomName":"q1-retro-action-items"}' >/dev/null 2>&1 || true
rc_api POST "groups.delete" '{"roomName":"q1-retro-action-items"}' >/dev/null 2>&1 || true

# Record baseline state
BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[].name] // []' 2>/dev/null || echo '[]')
BASELINE_CHANNELS=$(rc_api GET "channels.list?count=200" | jq '[.channels[].name] // []' 2>/dev/null || echo '[]')

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "retro_alpha_id": "${ALPHA_ID:-}",
  "retro_beta_id": "${BETA_ID:-}",
  "retro_gamma_id": "${GAMMA_ID:-}",
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
echo "Retro Alpha channel ID: ${ALPHA_ID:-unknown}"
echo "Retro Beta channel ID: ${BETA_ID:-unknown}"
echo "Retro Gamma channel ID: ${GAMMA_ID:-unknown}"
