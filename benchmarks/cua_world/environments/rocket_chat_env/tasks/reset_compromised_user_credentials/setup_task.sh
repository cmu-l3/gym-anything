#!/bin/bash
set -euo pipefail

echo "=== Setting up reset_compromised_user_credentials task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Verify Rocket.Chat API is reachable
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# Verify login credentials work
for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

if ! api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
  echo "ERROR: Task login credentials are not valid yet"
  exit 1
fi

# Clean state: Create dev.lead user and inject TOTP
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Delete dev.lead if it already exists from a previous run
  TARGET_USER_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/users.info?username=dev.lead" 2>/dev/null || true)
  TARGET_USER_ID=$(echo "$TARGET_USER_INFO" | jq -r '.user._id // empty' 2>/dev/null || true)

  if [ -n "$TARGET_USER_ID" ]; then
    echo "Deleting pre-existing dev.lead user"
    curl -sS -X POST \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      -H "Content-Type: application/json" \
      -d "{\"userId\":\"$TARGET_USER_ID\"}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/users.delete" 2>/dev/null || true
    sleep 1
  fi

  # Create dev.lead with an unknown initial password
  echo "Creating dev.lead user"
  curl -sS -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"Lead Developer\",\"email\":\"dev.lead@rocketchat.local\",\"password\":\"UnknownInitPass123!\",\"username\":\"dev.lead\",\"verified\":true,\"requirePasswordChange\":false}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/users.create" > /dev/null 2>&1

  sleep 2

  # Inject TOTP via MongoDB directly to simulate an enabled 2FA state
  echo "Injecting TOTP configuration for dev.lead"
  docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/rocketchat?directConnection=true" --eval "db.users.updateOne({username: 'dev.lead'}, {\$set: {'services.totp': {enabled: true, secret: 'JBSWY3DPEHPK3PXP'}}})" > /dev/null 2>&1

fi

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

take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="