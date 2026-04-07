#!/bin/bash
set -euo pipefail

echo "=== Exporting create_custom_user_status task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record task end and start times
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Use API to fetch the current list of custom statuses
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

STATUSES_JSON="{}"
if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Query custom user statuses endpoint
  STATUSES_JSON=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/custom-user-status.list" 2>/dev/null || echo "{}")
else
  echo "WARNING: Could not authenticate to Rocket.Chat API to export statuses."
fi

# Package all data into a JSON file for the verifier
TEMP_JSON=$(mktemp /tmp/custom_status_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "statuses_response": $STATUSES_JSON,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move file cleanly handling permissions
rm -f /tmp/custom_status_result.json 2>/dev/null || sudo rm -f /tmp/custom_status_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/custom_status_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/custom_status_result.json
chmod 666 /tmp/custom_status_result.json 2>/dev/null || sudo chmod 666 /tmp/custom_status_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete: /tmp/custom_status_result.json"