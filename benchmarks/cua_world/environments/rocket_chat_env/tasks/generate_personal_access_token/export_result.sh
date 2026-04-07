#!/bin/bash
set -euo pipefail

echo "=== Exporting Generate Personal Access Token results ==="

source /workspace/scripts/task_utils.sh

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/gitlab_token.txt"
TOKEN_NAME="gitlab-ci"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Verify Output File
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_LENGTH=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Read content (trim whitespace)
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | tr -d '[:space:]')
    FILE_LENGTH=${#FILE_CONTENT}
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Verify Token in API
API_TOKEN_FOUND="false"
API_TOKEN_CREATED_AT=""
API_TOKEN_CREATED_DURING_TASK="false"

# Login to check API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
    TOKENS_JSON=$(curl -sS -X GET \
        -H "X-Auth-Token: $AUTH_TOKEN" \
        -H "X-User-Id: $USER_ID" \
        "${ROCKETCHAT_BASE_URL}/api/v1/users.getPersonalAccessTokens" 2>/dev/null || true)
    
    # Find specific token object
    TOKEN_OBJ=$(echo "$TOKENS_JSON" | jq -r --arg name "$TOKEN_NAME" '.tokens[]? | select(.name == $name)')
    
    if [ -n "$TOKEN_OBJ" ] && [ "$TOKEN_OBJ" != "null" ]; then
        API_TOKEN_FOUND="true"
        # Rocket.Chat returns createdAt in ISO 8601 usually
        API_TOKEN_CREATED_AT=$(echo "$TOKEN_OBJ" | jq -r '.createdAt // empty')
        
        # Convert ISO to timestamp for comparison if possible, or just trust existence if setup cleaned it
        # Simple check: if we cleaned it in setup, and it exists now, it's new.
        # But let's try to be precise.
        if [ -n "$API_TOKEN_CREATED_AT" ]; then
             TOKEN_TS=$(date -d "$API_TOKEN_CREATED_AT" +%s 2>/dev/null || echo "0")
             if [ "$TOKEN_TS" -ge "$TASK_START_TIME" ]; then
                 API_TOKEN_CREATED_DURING_TASK="true"
             fi
        fi
    fi
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "file_exists": $FILE_EXISTS,
    "file_content_length": $FILE_LENGTH,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "api_token_found": $API_TOKEN_FOUND,
    "api_token_name": "$TOKEN_NAME",
    "api_token_created_at": "$API_TOKEN_CREATED_AT",
    "api_token_created_during_task": $API_TOKEN_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="