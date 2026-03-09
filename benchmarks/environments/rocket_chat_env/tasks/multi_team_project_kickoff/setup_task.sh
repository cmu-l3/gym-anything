#!/bin/bash
set -euo pipefail

echo "=== Setting up multi_team_project_kickoff task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="multi_team_project_kickoff"

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

create_user_if_not_exists "fe.lead" "Frontend Lead" "fe.lead@company.local"
create_user_if_not_exists "be.lead" "Backend Lead" "be.lead@company.local"
create_user_if_not_exists "qa.tester" "QA Tester" "qa.tester@company.local"
create_user_if_not_exists "ux.designer" "UX Designer" "ux.designer@company.local"
create_user_if_not_exists "pm.coordinator" "PM Coordinator" "pm.coordinator@company.local"
create_user_if_not_exists "devops.lead" "DevOps Lead" "devops.lead@company.local"

echo "All project team users created"

# Clean up any pre-existing project channels
for ch in phoenix-migration phoenix-frontend phoenix-backend phoenix-devops; do
  rc_api POST "channels.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
  rc_api POST "groups.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
done

sleep 1

# Record baseline
BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[].name] // []' 2>/dev/null || echo '[]')
BASELINE_CHANNELS=$(rc_api GET "channels.list?count=200" | jq '[.channels[].name] // []' 2>/dev/null || echo '[]')

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "baseline_groups": ${BASELINE_GROUPS},
  "baseline_channels": ${BASELINE_CHANNELS}
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
