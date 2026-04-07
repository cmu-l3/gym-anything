#!/bin/bash
set -euo pipefail

echo "=== Exporting archive_project_channel result ==="

source /workspace/scripts/task_utils.sh

# Anti-gaming: Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Login to API to inspect state
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

CHANNEL_FOUND="false"
IS_ARCHIVED="false"
IS_RO="false"
UPDATED_AT=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # 2. Query Channel Info
  INFO_RESP=$(curl -sS -X GET \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=project-alpha" 2>/dev/null)
  
  # Check if channel exists (success: true)
  SUCCESS=$(echo "$INFO_RESP" | jq -r '.success // false')
  
  if [ "$SUCCESS" == "true" ]; then
    CHANNEL_FOUND="true"
    IS_ARCHIVED=$(echo "$INFO_RESP" | jq -r '.channel.archived // false')
    IS_RO=$(echo "$INFO_RESP" | jq -r '.channel.ro // false')
    UPDATED_AT=$(echo "$INFO_RESP" | jq -r '.channel._updatedAt // empty')
  else
    echo "Channel 'project-alpha' not found via API (possibly deleted)"
    CHANNEL_FOUND="false"
  fi
else
  echo "ERROR: Could not log in to export results"
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "channel_found": $CHANNEL_FOUND,
    "is_archived": $IS_ARCHIVED,
    "is_read_only": $IS_RO,
    "channel_updated_at": "$UPDATED_AT",
    "task_start_ts": $TASK_START,
    "task_end_ts": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="