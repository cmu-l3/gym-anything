#!/bin/bash
set -euo pipefail

echo "=== Exporting assign_channel_moderator result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
CHANNEL_ID=$(cat /tmp/target_channel_id.txt 2>/dev/null || echo "")
AGENT_ID=$(cat /tmp/target_agent_id.txt 2>/dev/null || echo "")

# Data collection variables
API_HAS_ROLE="false"
MONGO_HAS_ROLE="false"
CHANNEL_NAME="release-updates"

# 3. Method 1: API Verification
echo "Verifying via API..."
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ] && [ -n "$CHANNEL_ID" ] && [ -n "$AGENT_ID" ]; then
  ROLES_RESP=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/channels.roles?roomId=${CHANNEL_ID}" 2>/dev/null || true)
  
  # Check if agent.user has "moderator" role in the returned list
  # The API returns an array of objects like { "u": {_id: "..."}, "roles": ["moderator", ...] }
  IS_MOD_API=$(echo "$ROLES_RESP" | jq -r --arg uid "$AGENT_ID" \
    '.roles[]? | select(.u._id == $uid and (.roles | index("moderator") != null)) | .u._id' 2>/dev/null || true)
  
  if [ -n "$IS_MOD_API" ]; then
    API_HAS_ROLE="true"
    echo "API confirmed moderator role."
  else
    echo "API did not find moderator role."
  fi
fi

# 4. Method 2: MongoDB Verification (Independent Check)
# We check the 'rocketchat_subscription' collection for the user's subscription to the room
echo "Verifying via MongoDB..."
if [ -n "$CHANNEL_ID" ] && [ -n "$AGENT_ID" ]; then
  # Use docker exec to query mongodb
  # We look for a document where 'rid' is channel_id, 'u._id' is agent_id, and 'roles' array contains 'moderator'
  MONGO_CHECK=$(docker exec rc-mongodb mongosh --quiet --eval \
    "db.getSiblingDB('rocketchat').rocketchat_subscription.countDocuments({ 'rid': '$CHANNEL_ID', 'u._id': '$AGENT_ID', 'roles': 'moderator' })" \
    2>/dev/null || echo "0")
  
  # mongosh output might contain extra lines, extract the last number
  MONGO_COUNT=$(echo "$MONGO_CHECK" | grep -oE '[0-9]+' | tail -n 1 || echo "0")
  
  if [ "$MONGO_COUNT" -gt 0 ]; then
    MONGO_HAS_ROLE="true"
    echo "MongoDB confirmed moderator role."
  else
    echo "MongoDB did not find moderator role."
  fi
fi

# 5. Check if application is running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "api_has_role": $API_HAS_ROLE,
    "mongo_has_role": $MONGO_HAS_ROLE,
    "app_was_running": $APP_RUNNING,
    "channel_id": "$CHANNEL_ID",
    "agent_id": "$AGENT_ID",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="