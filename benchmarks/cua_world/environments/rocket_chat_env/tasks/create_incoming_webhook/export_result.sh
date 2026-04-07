#!/bin/bash
set -euo pipefail

echo "=== Exporting create_incoming_webhook results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check File Existence and Content
URL_FILE="/home/ga/webhook_url.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_VALID_URL="false"

if [ -f "$URL_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$URL_FILE" | tr -d '[:space:]') # Trim whitespace
    if [[ "$FILE_CONTENT" =~ ^http://localhost:3000/hooks/[a-zA-Z0-9]+$ ]]; then
        FILE_VALID_URL="true"
    fi
fi

# 2. Query Rocket.Chat API for Integration and Message
INTEGRATION_FOUND="false"
INTEGRATION_DATA="{}"
MESSAGE_FOUND="false"
MESSAGE_DATA="{}"

# Authenticate
LOGIN_JSON=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

TOKEN=$(echo "$LOGIN_JSON" | jq -r '.data.authToken // empty')
USERID=$(echo "$LOGIN_JSON" | jq -r '.data.userId // empty')

if [ -n "$TOKEN" ] && [ -n "$USERID" ]; then
    AUTH_H1="X-Auth-Token: $TOKEN"
    AUTH_H2="X-User-Id: $USERID"

    # Find the integration
    # We look for one created AFTER task start to ensure freshness, matching name
    INTEGRATIONS_RESP=$(curl -sS -H "$AUTH_H1" -H "$AUTH_H2" "${ROCKETCHAT_BASE_URL}/api/v1/integrations.list")
    
    # Filter for our specific integration
    # We check for name "CI/CD Pipeline"
    INTEGRATION_DATA=$(echo "$INTEGRATIONS_RESP" | jq -c '.integrations[] | select(.name == "CI/CD Pipeline")' | head -n 1 || echo "{}")
    
    if [ "$INTEGRATION_DATA" != "{}" ] && [ -n "$INTEGRATION_DATA" ]; then
        INTEGRATION_FOUND="true"
    fi

    # Find the message in #release-updates
    # We search for the specific text
    TARGET_TEXT="Build #1042 deployed to production successfully. Version: 8.1.0"
    HISTORY_RESP=$(curl -sS -G -H "$AUTH_H1" -H "$AUTH_H2" \
        --data-urlencode "roomName=release-updates" \
        --data-urlencode "count=50" \
        "${ROCKETCHAT_BASE_URL}/api/v1/channels.history")
    
    # jq filter to find message with exact text
    MESSAGE_DATA=$(echo "$HISTORY_RESP" | jq -c --arg txt "$TARGET_TEXT" '.messages[] | select(.msg == $txt)' | head -n 1 || echo "{}")

    if [ "$MESSAGE_DATA" != "{}" ] && [ -n "$MESSAGE_DATA" ]; then
        MESSAGE_FOUND="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_content": "$FILE_CONTENT",
    "file_valid_url": $FILE_VALID_URL,
    "integration_found": $INTEGRATION_FOUND,
    "integration_data": $INTEGRATION_DATA,
    "message_found": $MESSAGE_FOUND,
    "message_data": $MESSAGE_DATA
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"