#!/bin/bash
set -euo pipefail

echo "=== Exporting task results ==="

ROCKETCHAT_BASE_URL="http://localhost:3000"
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
AGENT_USER="agent.user"
AGENT_PASS="AgentPass123!"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Authenticate as Admin to check permissions
echo "Authenticating as Admin..."
ADMIN_LOGIN=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

ADMIN_TOKEN=$(echo "$ADMIN_LOGIN" | jq -r '.data.authToken // empty')
ADMIN_UID=$(echo "$ADMIN_LOGIN" | jq -r '.data.userId // empty')

CURRENT_ROLES="[]"
PERMISSIONS_FETCHED="false"

if [ -n "$ADMIN_TOKEN" ]; then
    # Fetch current permissions
    PERM_LIST=$(curl -sS -X GET \
      -H "X-Auth-Token: $ADMIN_TOKEN" \
      -H "X-User-Id: $ADMIN_UID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/permissions.listAll?updatedSince=2000-01-01T00:00:00.000Z" 2>/dev/null)

    # Extract roles for 'create-c'
    CURRENT_ROLES=$(echo "$PERM_LIST" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    found = False
    for p in data.get('update', []):
        if p.get('_id') == 'create-c':
            print(json.dumps(p.get('roles', [])))
            found = True
            break
    if not found: print('[]')
except: print('[]')
" 2>/dev/null)
    PERMISSIONS_FETCHED="true"
fi

# 2. Functional Test: Authenticate as Agent User (Regular User) and try to create a channel
echo "Authenticating as Agent User for functional test..."
AGENT_LOGIN=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${AGENT_USER}\",\"password\":\"${AGENT_PASS}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AGENT_TOKEN=$(echo "$AGENT_LOGIN" | jq -r '.data.authToken // empty')
AGENT_UID=$(echo "$AGENT_LOGIN" | jq -r '.data.userId // empty')

FUNCTIONAL_TEST_ATTEMPTED="false"
CREATION_ALLOWED="unknown"
ERROR_TYPE=""

if [ -n "$AGENT_TOKEN" ]; then
    FUNCTIONAL_TEST_ATTEMPTED="true"
    TEST_CHANNEL="test-perm-$(date +%s)"
    
    # Attempt to create channel
    CREATE_RESP=$(curl -sS -X POST \
      -H "X-Auth-Token: $AGENT_TOKEN" \
      -H "X-User-Id: $AGENT_UID" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"$TEST_CHANNEL\", \"readOnly\":false}" \
      "${ROCKETCHAT_BASE_URL}/api/v1/channels.create" 2>/dev/null)
    
    IS_SUCCESS=$(echo "$CREATE_RESP" | jq -r '.success')
    
    if [ "$IS_SUCCESS" = "true" ]; then
        CREATION_ALLOWED="true"
        # Cleanup: Delete the channel if it was created (requires admin)
        CHANNEL_ID=$(echo "$CREATE_RESP" | jq -r '.channel._id // empty')
        if [ -n "$CHANNEL_ID" ] && [ -n "$ADMIN_TOKEN" ]; then
            curl -sS -X POST \
              -H "X-Auth-Token: $ADMIN_TOKEN" \
              -H "X-User-Id: $ADMIN_UID" \
              -H "Content-Type: application/json" \
              -d "{\"roomId\":\"$CHANNEL_ID\"}" \
              "${ROCKETCHAT_BASE_URL}/api/v1/channels.delete" >/dev/null 2>&1 || true
        fi
    else
        CREATION_ALLOWED="false"
        ERROR_TYPE=$(echo "$CREATE_RESP" | jq -r '.errorType // .error // "unknown"')
    fi
fi

# 3. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "permissions_fetched": $PERMISSIONS_FETCHED,
    "current_roles": $CURRENT_ROLES,
    "functional_test": {
        "attempted": $FUNCTIONAL_TEST_ATTEMPTED,
        "creation_allowed": "$CREATION_ALLOWED",
        "error_type": "$ERROR_TYPE"
    },
    "initial_roles_file_exists": $([ -f /tmp/initial_create_c_roles.json ] && echo "true" || echo "false"),
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