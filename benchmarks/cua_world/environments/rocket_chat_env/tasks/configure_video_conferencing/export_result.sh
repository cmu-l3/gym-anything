#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_video_conferencing task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Retrieve current settings from Rocket.Chat API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || echo "{}")

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "{}" > "$TEMP_JSON"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Fetch each target setting and append to JSON result file
  for setting in Jitsi_Enabled Jitsi_Domain Jitsi_Open_New_Window Jitsi_Enable_Channels Jitsi_Enable_Direct_Messages; do
    VAL=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings/$setting" | jq -r '.value // empty')
    
    # Save into JSON safely
    jq --arg k "$setting" --arg v "$VAL" '.[$k] = $v' "$TEMP_JSON" > "${TEMP_JSON}.tmp" && mv "${TEMP_JSON}.tmp" "$TEMP_JSON"
  done
else
  echo "WARNING: Could not authenticate to fetch settings"
fi

# Embed start time for anti-gaming verification
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
jq --arg ts "$TASK_START" '.task_start = $ts' "$TEMP_JSON" > "${TEMP_JSON}.tmp" && mv "${TEMP_JSON}.tmp" "$TEMP_JSON"

# Move output to standardized location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON exported:"
cat /tmp/task_result.json

echo "=== Export complete ==="