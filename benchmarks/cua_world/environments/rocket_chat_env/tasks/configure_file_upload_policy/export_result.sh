#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_file_upload_policy result ==="

source /workspace/scripts/task_utils.sh

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)

# Authenticate as admin to fetch settings
LOGIN_JSON=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_JSON" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_JSON" | jq -r '.data.userId // empty')

SETTINGS_DATA="{}"
MESSAGES_DATA="[]"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  echo "Fetching final settings configuration..."
  
  # Get Max File Size
  MAX_SIZE_JSON=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/FileUpload_MaxFileSize")
  MAX_SIZE=$(echo "$MAX_SIZE_JSON" | jq -r '.value // -1')

  # Get Whitelist
  WHITELIST_JSON=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/FileUpload_MediaTypeWhiteList")
  WHITELIST=$(echo "$WHITELIST_JSON" | jq -r '.value // ""')

  # Get Protect Files
  PROTECT_JSON=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/FileUpload_ProtectFiles")
  PROTECT=$(echo "$PROTECT_JSON" | jq -r '.value // false')

  # Construct Settings JSON object
  # Escape quotes in whitelist just in case
  SAFE_WHITELIST=$(echo "$WHITELIST" | sed 's/"/\\"/g')
  SETTINGS_DATA="{\"max_file_size\": $MAX_SIZE, \"media_type_whitelist\": \"$SAFE_WHITELIST\", \"protect_files\": $PROTECT}"

  echo "Fetching #general channel history..."
  # Get General Channel ID (usually GENERAL, but safer to lookup)
  CHANNELS_JSON=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=general")
  ROOM_ID=$(echo "$CHANNELS_JSON" | jq -r '.channel._id // empty')

  if [ -n "$ROOM_ID" ]; then
    # Fetch recent messages
    HISTORY_JSON=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.history?roomId=${ROOM_ID}&count=20")
    
    # Filter for messages sent by admin after task start
    MESSAGES_DATA=$(echo "$HISTORY_JSON" | jq -c "[.messages[] | select(.u.username == \"${ROCKETCHAT_TASK_USERNAME}\")]")
  fi
else
  echo "WARNING: Could not authenticate to export results."
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "task_start_time": $TASK_START_TIME,
  "task_end_time": $TASK_END_TIME,
  "settings": $SETTINGS_DATA,
  "messages": $MESSAGES_DATA,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="