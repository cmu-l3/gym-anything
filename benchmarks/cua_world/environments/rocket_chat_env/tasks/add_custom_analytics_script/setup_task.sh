#!/bin/bash
set -euo pipefail

echo "=== Setting up add_custom_analytics_script task ==="

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

# Clean state: Ensure the Custom Script setting is empty
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  echo "Clearing pre-existing 'CustomScript_Logged_In' setting..."
  curl -sS -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d "{\"value\":\"\"}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/CustomScript_Logged_In" 2>/dev/null || true
fi

# Create the snippet file for the agent to find
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/analytics_snippet.js << 'EOF'
window.InternalTracker = {
  id: "TRACKER-998877",
  start: new Date().toISOString(),
  env: "production",
  capture: function(e) { console.log("Event:", e); }
};
console.log("Analytics Loaded");
EOF
chown ga:ga /home/ga/Documents/analytics_snippet.js
chmod 644 /home/ga/Documents/analytics_snippet.js

# Record snippet file access time for anti-gaming checks
stat -c %X /home/ga/Documents/analytics_snippet.js > /tmp/initial_snippet_atime

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