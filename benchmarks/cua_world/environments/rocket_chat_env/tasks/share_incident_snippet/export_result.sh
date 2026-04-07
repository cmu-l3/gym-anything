#!/bin/bash
set -euo pipefail

echo "=== Exporting share_incident_snippet result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

FILE_FOUND="false"
FILE_NAME=""
FILE_CONTENT=""
IS_NEW="false"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  CHANNEL_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.info?roomName=release-updates" 2>/dev/null || true)
  CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.channel._id // empty' 2>/dev/null || true)

  if [ -n "$CHANNEL_ID" ]; then
    FILES=$(curl -sS \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.files?roomId=${CHANNEL_ID}" 2>/dev/null || true)

    # Get the latest file named rollback_procedure.sh
    FILE_INFO=$(echo "$FILES" | jq -r '[.files[]? | select(.name == "rollback_procedure.sh")] | sort_by(.uploadedAt) | last // empty')

    if [ -n "$FILE_INFO" ]; then
      FILE_FOUND="true"
      FILE_NAME=$(echo "$FILE_INFO" | jq -r '.name')
      FILE_URL=$(echo "$FILE_INFO" | jq -r '.url')
      FILE_UPLOADED_AT=$(echo "$FILE_INFO" | jq -r '.uploadedAt')
      
      # Convert ISO8601 to Unix timestamp using Python (handles timezone)
      FILE_TS=$(python3 -c "from datetime import datetime; import sys; ts=sys.argv[1].replace('Z', '+00:00'); print(int(datetime.fromisoformat(ts).timestamp()))" "$FILE_UPLOADED_AT" 2>/dev/null || echo "0")
      
      if [ "$FILE_TS" -ge "$TASK_START" ]; then
        IS_NEW="true"
      fi

      if [ -n "$FILE_URL" ]; then
        # Download file content
        FILE_CONTENT=$(curl -sS \
          -H "X-Auth-Token: $AUTH_TOKEN" \
          -H "X-User-Id: $USER_ID" \
          "${ROCKETCHAT_BASE_URL}${FILE_URL}" 2>/dev/null || true)
      fi
    fi
  fi
fi

# Dump to JSON safely
TEMP_JSON=$(mktemp /tmp/share_incident_snippet_result.XXXXXX.json)
python3 -c '
import json, sys, os
data = {
    "task_start": int(sys.argv[1]),
    "task_end": int(sys.argv[2]),
    "file_found": sys.argv[3] == "true",
    "file_name": sys.argv[4],
    "file_content": sys.argv[5],
    "is_new": sys.argv[6] == "true"
}
with open(sys.argv[7], "w") as f:
    json.dump(data, f)
' "$TASK_START" "$TASK_END" "$FILE_FOUND" "$FILE_NAME" "$FILE_CONTENT" "$IS_NEW" "$TEMP_JSON"

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."