#!/bin/bash
set -euo pipefail

echo "=== Exporting disable_public_registration task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM evaluation
take_screenshot /tmp/task_final.png

# Gather timestamps and initial state
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_STATE=$(cat /tmp/initial_registration_state.txt 2>/dev/null || echo "Public")

# Query current configuration state using REST API
LOGIN_PAYLOAD=$(jq -nc --arg user "$ROCKETCHAT_TASK_USERNAME" --arg pass "$ROCKETCHAT_TASK_PASSWORD" '{user: $user, password: $pass}')
LOGIN_RESP=$(curl -sS -X POST -H "Content-Type: application/json" -d "$LOGIN_PAYLOAD" "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

CURRENT_STATE="unknown"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  echo "Querying current Accounts_RegistrationForm state..."
  SETTING_RESP=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Accounts_RegistrationForm" 2>/dev/null)
  
  CURRENT_STATE=$(echo "$SETTING_RESP" | jq -r '.value // "unknown"')
fi

echo "Initial State: $INITIAL_STATE"
echo "Current State: $CURRENT_STATE"

# Check if browser is still running
APP_RUNNING="false"
if pgrep -f 'firefox|epiphany' >/dev/null 2>&1; then
  APP_RUNNING="true"
fi

# Prepare JSON output payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_state": "$INITIAL_STATE",
    "current_state": "$CURRENT_STATE",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location handling permissions safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="