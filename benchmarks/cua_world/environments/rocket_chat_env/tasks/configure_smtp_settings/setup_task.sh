#!/bin/bash
set -euo pipefail

echo "=== Setting up Configure SMTP Settings task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Rocket.Chat is reachable
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# Reset SMTP settings to defaults to ensure clean state
echo "Resetting SMTP settings to clean state..."

# Login to get token
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
    # Helper to reset a setting
    reset_setting() {
        local key="$1"
        local value="$2"
        curl -sS -X POST \
          -H "X-Auth-Token: $AUTH_TOKEN" \
          -H "X-User-Id: $USER_ID" \
          -H "Content-Type: application/json" \
          -d "{\"value\": \"$value\"}" \
          "${ROCKETCHAT_BASE_URL}/api/v1/settings/$key" >/dev/null || true
    }
    
    # Reset boolean
    reset_bool_setting() {
        local key="$1"
        local value="$2"
        curl -sS -X POST \
          -H "X-Auth-Token: $AUTH_TOKEN" \
          -H "X-User-Id: $USER_ID" \
          -H "Content-Type: application/json" \
          -d "{\"value\": $value}" \
          "${ROCKETCHAT_BASE_URL}/api/v1/settings/$key" >/dev/null || true
    }

    reset_setting "SMTP_Host" ""
    reset_setting "SMTP_Port" ""
    reset_setting "SMTP_Username" ""
    reset_setting "SMTP_Password" ""
    reset_setting "SMTP_Protocol" "smtp"
    reset_bool_setting "SMTP_IgnoreTLS" "false"
    
    echo "Settings reset complete."
else
    echo "WARNING: Could not login to reset settings. Task may start with stale state."
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

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="