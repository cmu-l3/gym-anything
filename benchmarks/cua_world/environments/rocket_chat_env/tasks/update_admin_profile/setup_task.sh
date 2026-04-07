#!/bin/bash
set -euo pipefail

echo "=== Setting up update_admin_profile task ==="

source /workspace/scripts/task_utils.sh

# 1. Generate the avatar image
AVATAR_PATH="/home/ga/it_avatar.png"
echo "Generating avatar image at $AVATAR_PATH..."

# Create a blue square with "IT" text using ImageMagick
convert -size 200x200 xc:blue -fill white -gravity center -pointsize 80 -annotate +0+0 "IT" "$AVATAR_PATH"
chown ga:ga "$AVATAR_PATH"

# 2. Record initial state (Anti-gaming)
date +%s > /tmp/task_start_timestamp

# Wait for API to be ready
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# Login to API to get initial user info
echo "Logging in to API to record initial state..."
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Get user info
  USER_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/users.info?userId=$USER_ID" 2>/dev/null)
  
  # Extract relevant fields
  INITIAL_NAME=$(echo "$USER_INFO" | jq -r '.user.name // empty')
  INITIAL_STATUS=$(echo "$USER_INFO" | jq -r '.user.statusText // empty')
  INITIAL_AVATAR_ETAG=$(echo "$USER_INFO" | jq -r '.user.avatarETag // empty')

  # Save to initial state file
  cat > /tmp/initial_user_state.json <<EOF
{
  "name": "$INITIAL_NAME",
  "statusText": "$INITIAL_STATUS",
  "avatarETag": "$INITIAL_AVATAR_ETAG"
}
EOF
  echo "Initial state recorded: Name='$INITIAL_NAME', Status='$INITIAL_STATUS', ETag='$INITIAL_AVATAR_ETAG'"
else
  echo "WARNING: Failed to record initial API state. Anti-gaming checks might be limited."
  echo "{}" > /tmp/initial_user_state.json
fi

# 3. Prepare Browser
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2

take_screenshot /tmp/task_start.png
echo "=== Task setup complete ==="