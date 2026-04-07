#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_maintenance_announcement result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

# Re-authenticate to query the final state of the settings
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

# Dump all system settings to JSON for the verifier
curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings" > /tmp/all_settings.json 2>/dev/null || echo "{}" > /tmp/all_settings.json

# Create metadata JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "settings_exported": true
}
EOF

# Move files to permanent final locations handling potential permission issues
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

chmod 666 /tmp/all_settings.json 2>/dev/null || sudo chmod 666 /tmp/all_settings.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="