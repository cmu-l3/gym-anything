#!/bin/bash
set -euo pipefail

echo "=== Exporting Bulk User Import Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")

# Login to API to check results
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
  echo "ERROR: Failed to authenticate for export"
  # Create failed result
  echo '{"error": "API Auth Failed"}' > /tmp/task_result.json
  exit 0
fi

# Define expected users
EXPECTED_USERS=("intern.chen" "intern.rodriguez" "intern.kd" "intern.jensen" "intern.patel")
USER_RESULTS="[]"

echo "Checking user status..."

for username in "${EXPECTED_USERS[@]}"; do
  # Fetch user info
  USER_INFO=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/users.info?username=$username" 2>/dev/null || true)
  
  EXISTS=$(echo "$USER_INFO" | jq -r '.success // false')
  
  if [ "$EXISTS" = "true" ]; then
    NAME=$(echo "$USER_INFO" | jq -r '.user.name // empty')
    EMAIL=$(echo "$USER_INFO" | jq -r '.user.emails[0].address // empty')
    CREATED_AT_ISO=$(echo "$USER_INFO" | jq -r '.user.createdAt // empty')
    
    # Convert ISO to timestamp
    CREATED_AT_TS=$(date -d "$CREATED_AT_ISO" +%s 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$CREATED_AT_TS" -gt "$TASK_START" ]; then
      CREATED_DURING_TASK="true"
    else
      CREATED_DURING_TASK="false"
    fi

    # Append to results
    USER_JSON=$(jq -n \
      --arg u "$username" \
      --arg n "$NAME" \
      --arg e "$EMAIL" \
      --argjson c "$CREATED_DURING_TASK" \
      '{username: $u, found: true, actual_name: $n, actual_email: $e, created_during_task: $c}')
  else
    USER_JSON=$(jq -n \
      --arg u "$username" \
      '{username: $u, found: false}')
  fi
  
  USER_RESULTS=$(echo "$USER_RESULTS" | jq --argjson u "$USER_JSON" '. + [$u]')
done

# Get Current Total Count
CURRENT_COUNT=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/users.list?count=1" | jq '.total // 0')

# Create Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "initial_user_count": $INITIAL_COUNT,
  "current_user_count": $CURRENT_COUNT,
  "user_results": $USER_RESULTS,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="