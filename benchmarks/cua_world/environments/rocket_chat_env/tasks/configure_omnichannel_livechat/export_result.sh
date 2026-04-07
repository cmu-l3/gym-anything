#!/bin/bash
set -euo pipefail

echo "=== Exporting Omnichannel LiveChat configuration result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
LIVECHAT_ENABLED="false"
AGENT_REGISTERED="false"
DEPT_EXISTS="false"
DEPT_ENABLED="false"
AGENT_ASSIGNED="false"
DEPT_NAME_FOUND=""

# Authenticate to query API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  
  # 1. Check if LiveChat is enabled
  SETTINGS_RESP=$(curl -sS -X GET \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Livechat_enabled" 2>/dev/null || true)
  LIVECHAT_ENABLED=$(echo "$SETTINGS_RESP" | jq -r '.value // false' 2>/dev/null || echo "false")
  
  # 2. Check if agent.user is a LiveChat agent
  AGENTS_RESP=$(curl -sS -X GET \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/livechat/users/agent?count=100" 2>/dev/null || true)
  
  # Check if agent.user is in the list
  if echo "$AGENTS_RESP" | jq -e '.users[]? | select(.username == "agent.user")' >/dev/null 2>&1; then
    AGENT_REGISTERED="true"
  fi
  
  # 3. Check if 'Technical Support' department exists
  DEPTS_RESP=$(curl -sS -X GET \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/livechat/department?count=100" 2>/dev/null || true)
  
  # Find department ID
  DEPT_OBJ=$(echo "$DEPTS_RESP" | jq -r '.departments[]? | select(.name == "Technical Support")' 2>/dev/null || true)
  
  if [ -n "$DEPT_OBJ" ]; then
    DEPT_EXISTS="true"
    DEPT_ID=$(echo "$DEPT_OBJ" | jq -r '._id // empty')
    DEPT_ENABLED=$(echo "$DEPT_OBJ" | jq -r '.enabled // false')
    DEPT_NAME_FOUND="Technical Support"
    
    # 4. Check if agent is assigned to this department
    # Need to fetch specific department details to get agents
    if [ -n "$DEPT_ID" ]; then
      DEPT_DETAIL_RESP=$(curl -sS -X GET \
        -H "X-Auth-Token: $AUTH_TOKEN" \
        -H "X-User-Id: $USER_ID" \
        "${ROCKETCHAT_BASE_URL}/api/v1/livechat/department/${DEPT_ID}" 2>/dev/null || true)
      
      # The agents are usually in a separate endpoint or included depending on version
      # Let's try the agents endpoint for department
      DEPT_AGENTS_RESP=$(curl -sS -X GET \
        -H "X-Auth-Token: $AUTH_TOKEN" \
        -H "X-User-Id: $USER_ID" \
        "${ROCKETCHAT_BASE_URL}/api/v1/livechat/department/${DEPT_ID}/agents" 2>/dev/null || true)
      
      if echo "$DEPT_AGENTS_RESP" | jq -e '.agents[]? | select(.username == "agent.user")' >/dev/null 2>&1; then
        AGENT_ASSIGNED="true"
      else
         # Fallback: sometimes returned in main object in older APIs
         if echo "$DEPT_DETAIL_RESP" | jq -e '.agents[]? | select(.username == "agent.user")' >/dev/null 2>&1; then
           AGENT_ASSIGNED="true"
         fi
      fi
    fi
  fi
else
  echo "ERROR: Failed to authenticate for verification"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "livechat_enabled": $LIVECHAT_ENABLED,
    "agent_registered": $AGENT_REGISTERED,
    "department_exists": $DEPT_EXISTS,
    "department_enabled": $DEPT_ENABLED,
    "agent_assigned_to_dept": $AGENT_ASSIGNED,
    "department_name_found": "$DEPT_NAME_FOUND",
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