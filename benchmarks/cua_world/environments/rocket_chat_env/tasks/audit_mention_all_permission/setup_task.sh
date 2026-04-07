#!/bin/bash
set -euo pipefail

echo "=== Setting up audit_mention_all_permission task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming validation)
date +%s > /tmp/task_start_time.txt
rm -f /home/ga/mention_all_audit.txt 2>/dev/null || true

# Wait for API readiness
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# Login via API to get auth token
for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

LOGIN_JSON=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"$ROCKETCHAT_TASK_USERNAME\",\"password\":\"$ROCKETCHAT_TASK_PASSWORD\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

TOKEN=$(echo "$LOGIN_JSON" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_JSON" | jq -r '.data.userId // empty' 2>/dev/null || true)

if [ -z "$TOKEN" ] || [ -z "$USER_ID" ]; then
  echo "ERROR: Failed to login via API"
  exit 1
fi

# Randomize the 'mention-all' permission state for anti-gaming (prevent reliance on defaults)
# Core roles
ROLES=("admin")
POSSIBLE_ROLES=("user" "bot" "guest" "anonymous" "app")

# Shuffle and pick 1-2 additional roles
SHUFFLED=$(printf "%s\n" "${POSSIBLE_ROLES[@]}" | shuf)
COUNT=$(shuf -i 1-2 -n 1)
SELECTED=$(echo "$SHUFFLED" | head -n "$COUNT")

for role in $SELECTED; do
  ROLES+=("$role")
done

JSON_ROLES=$(printf '%s\n' "${ROLES[@]}" | jq -R . | jq -s .)

echo "Setting 'mention-all' permission to roles: ${ROLES[*]}"

UPDATE_PAYLOAD=$(jq -n --argjson roles "$JSON_ROLES" '{permissions: [{_id: "mention-all", roles: $roles}]}')

curl -sS -X POST \
  -H "X-Auth-Token: $TOKEN" \
  -H "X-User-Id: $USER_ID" \
  -H "Content-Type: application/json" \
  -d "$UPDATE_PAYLOAD" \
  "${ROCKETCHAT_BASE_URL}/api/v1/permissions.update" > /dev/null 2>&1 || true

# Save ground truth to file
echo "${ROLES[*]}" > /tmp/ground_truth_roles.txt
chmod 444 /tmp/ground_truth_roles.txt

# Start Firefox at Rocket.Chat login page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  DISPLAY=:1 wmctrl -l 2>/dev/null || true
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

# Final initial screenshot showing starting state
take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="