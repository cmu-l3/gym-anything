#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_global_notification_defaults result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Fetch the final setting state via API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

SETTING_RAW="{}"
SETTING_VALUE="{}"
FINAL_UPDATED_AT=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  SETTING_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Accounts_Default_User_Preferences" 2>/dev/null || true)
  
  FINAL_UPDATED_AT=$(echo "$SETTING_INFO" | jq -r '._updatedAt // empty' 2>/dev/null || true)
  
  # Ensure safely escaping the JSON output
  SETTING_RAW=$(echo "$SETTING_INFO" | jq -c '. // {}' 2>/dev/null || echo "{}")
  SETTING_VALUE=$(echo "$SETTING_INFO" | jq -c '.value // {}' 2>/dev/null || echo "{}")
fi

INITIAL_UPDATED_AT=$(cat /tmp/initial_updated_at.txt 2>/dev/null || echo "")
TASK_START_TS=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END_TS=$(date +%s)

# Create JSON result using a temp file for permissions safety
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_ts": $TASK_START_TS,
  "task_end_ts": $TASK_END_TS,
  "initial_updated_at": "$INITIAL_UPDATED_AT",
  "final_updated_at": "$FINAL_UPDATED_AT",
  "setting_value": $SETTING_VALUE,
  "setting_raw": $SETTING_RAW,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="