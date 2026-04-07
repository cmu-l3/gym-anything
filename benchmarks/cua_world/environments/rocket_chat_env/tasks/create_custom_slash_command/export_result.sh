#!/bin/bash
set -euo pipefail

echo "=== Exporting create_custom_slash_command results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather verification data via API
echo "Querying Rocket.Chat API for integrations..."

TASK_START_TIME=$(cat /tmp/task_start_timestamp.txt 2>/dev/null || echo "0")

# Login as admin
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

FOUND_INTEGRATION="null"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Fetch list of integrations
  # We look for one with command="deploy-status"
  # We assume slash commands are stored as outgoing webhooks with a trigger word/command
  INTEGRATIONS_JSON=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/integrations.list" 2>/dev/null || echo "{}")
  
  # Extract the specific integration if it exists
  FOUND_INTEGRATION=$(echo "$INTEGRATIONS_JSON" | \
    jq -c '.integrations[] | select(.command == "deploy-status")' 2>/dev/null | head -n 1 || echo "null")
else
  echo "ERROR: Failed to authenticate to export results"
fi

# 3. Create result JSON
# We use a temp file to avoid permission issues, then move it
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
  "task_start_time": $TASK_START_TIME,
  "task_end_time": $(date +%s),
  "found_integration": $FOUND_INTEGRATION,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Exported result to /tmp/task_result.json"
echo "=== Export complete ==="