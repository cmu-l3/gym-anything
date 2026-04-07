#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_file_upload_policy task ==="

source /workspace/scripts/task_utils.sh

# Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt
rm -f /tmp/task_result.json 2>/dev/null || true

# Wait for Rocket.Chat to be ready
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# Authenticate as admin to reset settings
echo "Authenticating as admin..."
LOGIN_JSON=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login")

AUTH_TOKEN=$(echo "$LOGIN_JSON" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_JSON" | jq -r '.data.userId // empty')

if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
  echo "ERROR: Failed to authenticate as admin"
  exit 1
fi

echo "Resetting File Upload settings to permissive defaults..."

# 1. Reset Max File Size to default (usually 0 or -1 or a large number like 209715200)
# Setting to 100MB (104857600) to ensure it's different from target
curl -sS -X POST \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  -H "Content-Type: application/json" \
  -d '{"value": 104857600}' \
  "${ROCKETCHAT_BASE_URL}/api/v1/settings/FileUpload_MaxFileSize" > /dev/null

# 2. Reset Media Type Whitelist to empty (allow all)
curl -sS -X POST \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  -H "Content-Type: application/json" \
  -d '{"value": ""}' \
  "${ROCKETCHAT_BASE_URL}/api/v1/settings/FileUpload_MediaTypeWhiteList" > /dev/null

# 3. Reset Protect Uploaded Files to false
curl -sS -X POST \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  -H "Content-Type: application/json" \
  -d '{"value": false}' \
  "${ROCKETCHAT_BASE_URL}/api/v1/settings/FileUpload_ProtectFiles" > /dev/null

# Record initial state for verification debugging
echo "Recording initial settings state..."
cat > /tmp/initial_settings.json <<EOF
{
  "max_size": 104857600,
  "whitelist": "",
  "protect": false
}
EOF

# Ensure browser is clean and ready
echo "Preparing Firefox..."
stop_firefox
prepare_firefox_runtime_profile

# Start Firefox at the home page
echo "Starting Firefox..."
restart_firefox "${ROCKETCHAT_BASE_URL}/home" 5

# Ensure window is maximized
focus_firefox
maximize_active_window

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="