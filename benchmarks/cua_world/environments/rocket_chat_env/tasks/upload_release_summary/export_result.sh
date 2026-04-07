#!/bin/bash
set -euo pipefail

echo "=== Exporting upload_release_summary results ==="

ROCKETCHAT_BASE_URL="http://localhost:3000"
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
CHANNEL_NAME="release-updates"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Authenticate via REST API to inspect channel state
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" \
  "$ROCKETCHAT_BASE_URL/api/v1/login" 2>/dev/null || echo "{}")

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

# Prepare result objects
API_ACCESSIBLE="false"
CHANNEL_FOUND="false"
CHANNEL_ID=""
FILES_JSON="[]"
MESSAGES_JSON="[]"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
    API_ACCESSIBLE="true"
    
    # Get channel info
    CHANNEL_INFO=$(curl -sS -G \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      --data-urlencode "roomName=$CHANNEL_NAME" \
      "$ROCKETCHAT_BASE_URL/api/v1/channels.info" 2>/dev/null || echo "{}")

    CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)

    if [ -n "$CHANNEL_ID" ]; then
        CHANNEL_FOUND="true"

        # Get recent files in channel (limit 20)
        FILES_JSON=$(curl -sS -G \
          -H "X-Auth-Token: $AUTH_TOKEN" \
          -H "X-User-Id: $USER_ID" \
          --data-urlencode "roomId=$CHANNEL_ID" \
          --data-urlencode "sort={\"uploadedAt\": -1}" \
          --data-urlencode "count=20" \
          "$ROCKETCHAT_BASE_URL/api/v1/channels.files" 2>/dev/null | jq -c '.files // []')

        # Get recent messages history (limit 50) to check for text
        MESSAGES_JSON=$(curl -sS -G \
          -H "X-Auth-Token: $AUTH_TOKEN" \
          -H "X-User-Id: $USER_ID" \
          --data-urlencode "roomId=$CHANNEL_ID" \
          --data-urlencode "count=50" \
          "$ROCKETCHAT_BASE_URL/api/v1/channels.history" 2>/dev/null | jq -c '.messages // []')
    fi
fi

# Create result JSON
# We use a temp file to avoid race conditions or permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "task_end_time": $TASK_END_TIME,
    "api_accessible": $API_ACCESSIBLE,
    "channel_found": $CHANNEL_FOUND,
    "channel_id": "$CHANNEL_ID",
    "channel_files": $FILES_JSON,
    "channel_messages": $MESSAGES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with liberal permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="