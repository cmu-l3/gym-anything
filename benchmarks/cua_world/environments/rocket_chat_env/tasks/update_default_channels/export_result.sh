#!/bin/bash
set -euo pipefail

echo "=== Exporting update_default_channels results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Authenticate to API to fetch verification data
# We use the admin credentials to verify the global settings and channel details
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

# 1. Check Channel 'announcements'
CHANNEL_EXISTS="false"
CHANNEL_RO="false"
CHANNEL_TOPIC=""
CHANNEL_CREATED_AT="0"

if [ -n "$AUTH_TOKEN" ]; then
  CHANNEL_INFO=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=announcements" 2>/dev/null)
  
  # Check if request was successful
  SUCCESS=$(echo "$CHANNEL_INFO" | jq -r '.success')
  
  if [ "$SUCCESS" == "true" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_RO=$(echo "$CHANNEL_INFO" | jq -r '.channel.ro')
    CHANNEL_TOPIC=$(echo "$CHANNEL_INFO" | jq -r '.channel.topic // empty')
    # timestamp is usually in ms or iso date, we'll store raw
    CHANNEL_CREATED_TS=$(echo "$CHANNEL_INFO" | jq -r '.channel.ts // empty')
    
    # Convert ISO timestamp to epoch for comparison if needed, though usually just existence is enough
    # RocketChat API returns TS strings like "2026-03-08T12:00:00.000Z"
    if [ -n "$CHANNEL_CREATED_TS" ]; then
      CHANNEL_CREATED_AT=$(date -d "$CHANNEL_CREATED_TS" +%s 2>/dev/null || echo "0")
    fi
  fi
fi

# 2. Check Default Channels Setting
DEFAULT_CHANNELS_VALUE=""
if [ -n "$AUTH_TOKEN" ]; then
  SETTINGS_INFO=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Default_Channels" 2>/dev/null)
  
  DEFAULT_CHANNELS_VALUE=$(echo "$SETTINGS_INFO" | jq -r '.value // empty')
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "channel_exists": $CHANNEL_EXISTS,
    "channel_ro": $CHANNEL_RO,
    "channel_topic": "$(echo "$CHANNEL_TOPIC" | sed 's/"/\\"/g')",
    "channel_created_at": $CHANNEL_CREATED_AT,
    "default_channels_value": "$(echo "$DEFAULT_CHANNELS_VALUE" | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result data saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="