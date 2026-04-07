#!/bin/bash
set -euo pipefail

echo "=== Exporting create_custom_role task result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END_TIME=$(date +%s)
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final evidence screenshot
take_screenshot /tmp/task_end.png

# Authenticate via API to extract final state
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
  echo "ERROR: Could not authenticate to export results."
  # Create a failure JSON so the verifier can handle it gracefully
  echo '{"error": "Export authentication failed"}' > /tmp/custom_role_result.json
  exit 0
fi

echo "Fetching final roles..."
ROLES_JSON=$(curl -sS \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/roles.list" 2>/dev/null || echo "{}")

echo "Fetching final permissions..."
PERMS_JSON=$(curl -sS \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/permissions.listAll" 2>/dev/null || echo "{}")

echo "Fetching final user info..."
USER_JSON=$(curl -sS \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/users.info?username=agent.user" 2>/dev/null || echo "{}")

# Package into a single JSON file using jq safely
TEMP_JSON=$(mktemp /tmp/custom_role_export.XXXXXX.json)
jq -n \
  --argjson roles "${ROLES_JSON:-{}}" \
  --argjson perms "${PERMS_JSON:-{}}" \
  --argjson user "${USER_JSON:-{}}" \
  --arg start "$TASK_START_TIME" \
  --arg end "$TASK_END_TIME" \
  '{
    roles_list: $roles, 
    permissions_list: $perms, 
    target_user: $user, 
    task_start: $start, 
    task_end: $end
  }' > "$TEMP_JSON"

# Move temp file to final destination safely
rm -f /tmp/custom_role_result.json 2>/dev/null || sudo rm -f /tmp/custom_role_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/custom_role_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/custom_role_result.json
chmod 666 /tmp/custom_role_result.json 2>/dev/null || sudo chmod 666 /tmp/custom_role_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export saved to /tmp/custom_role_result.json"
echo "=== Export complete ==="