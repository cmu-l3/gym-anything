#!/bin/bash
set -euo pipefail

echo "=== Exporting register_oauth_application task result ==="

source /workspace/scripts/task_utils.sh

# Record timing and initial state
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_oauth_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Authenticate via REST API to fetch results
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Fetch all OAuth apps
  APPS_JSON=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/oauth-apps.list" 2>/dev/null || echo '{"oauthApps":[]}')
  
  # Calculate current count
  CURRENT_COUNT=$(echo "$APPS_JSON" | jq '.oauthApps | length' 2>/dev/null || echo "0")
  
  # Search for the target app
  TARGET_APP=$(echo "$APPS_JSON" | jq -c '.oauthApps[]? | select(.name == "Release Dashboard")' 2>/dev/null | head -n 1)
  TARGET_APPS_COUNT=$(echo "$APPS_JSON" | jq '.oauthApps | map(select(.name == "Release Dashboard")) | length' 2>/dev/null || echo "0")
  
  cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "initial_count": $INITIAL_COUNT,
  "current_count": $CURRENT_COUNT,
  "target_apps_count": $TARGET_APPS_COUNT,
  "target_app": ${TARGET_APP:-null},
  "api_success": true
}
EOF
else
  cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "api_success": false
}
EOF
fi

# Move safely to /tmp
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="