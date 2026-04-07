#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_channel_notifications result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Task Start Time
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Fetch current settings from API
echo "Fetching final subscription settings..."

LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

SETTINGS_FOUND="false"
DESKTOP_NOTIF="unknown"
MOBILE_NOTIF="unknown"
EMAIL_NOTIF="unknown"
UPDATED_AT="0"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Get Room ID for #general
  CHANNEL_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=general" 2>/dev/null || true)
  ROOM_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)

  if [ -n "$ROOM_ID" ]; then
    # Get Subscription details for this room
    # Note: subscriptions.getOne requires roomId
    SUB_INFO=$(curl -sS \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/subscriptions.getOne?roomId=$ROOM_ID" 2>/dev/null || true)
    
    if [ "$(echo "$SUB_INFO" | jq -r '.success')" = "true" ]; then
        SETTINGS_FOUND="true"
        DESKTOP_NOTIF=$(echo "$SUB_INFO" | jq -r '.subscription.desktopNotifications // "default"')
        MOBILE_NOTIF=$(echo "$SUB_INFO" | jq -r '.subscription.mobilePushNotifications // "default"')
        EMAIL_NOTIF=$(echo "$SUB_INFO" | jq -r '.subscription.emailNotifications // "default"')
        UPDATED_AT_ISO=$(echo "$SUB_INFO" | jq -r '.subscription._updatedAt // empty')
        
        # Convert ISO date to timestamp if possible, otherwise 0
        if [ -n "$UPDATED_AT_ISO" ]; then
            UPDATED_AT=$(date -d "$UPDATED_AT_ISO" +%s 2>/dev/null || echo "0")
        fi
    fi
  fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "settings_found": $SETTINGS_FOUND,
    "desktop_notifications": "$DESKTOP_NOTIF",
    "mobile_notifications": "$MOBILE_NOTIF",
    "email_notifications": "$EMAIL_NOTIF",
    "updated_at_timestamp": $UPDATED_AT,
    "task_start_timestamp": $TASK_START_TIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="