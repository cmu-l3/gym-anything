#!/bin/bash
set -euo pipefail

echo "=== Exporting add_custom_analytics_script result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve Rocket.Chat API state for the Custom Script setting
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || echo "")
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || echo "")

SETTING_VALUE=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  SETTING_RESP=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/CustomScript_Logged_In" 2>/dev/null || true)
  
  SETTING_VALUE=$(echo "$SETTING_RESP" | jq -r '.value // empty' 2>/dev/null || echo "")
fi

# Get file access/modification times for the snippet
ATIME=$(stat -c %X /home/ga/Documents/analytics_snippet.js 2>/dev/null || echo "0")
INITIAL_ATIME=$(cat /tmp/initial_snippet_atime 2>/dev/null || echo "0")

# Dump everything to a JSON file for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
  --arg val "$SETTING_VALUE" \
  --arg atime "$ATIME" \
  --arg init_atime "$INITIAL_ATIME" \
  --arg auth "$AUTH_TOKEN" \
  '{
    "setting_value": $val,
    "file_accessed": ($atime > $init_atime),
    "api_success": ($auth != "")
  }' > "$TEMP_JSON"

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json