#!/bin/bash
set -euo pipefail

echo "=== Setting up task: Restrict Public Channel Creation Permission ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

ROCKETCHAT_BASE_URL="http://localhost:3000"
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# Wait for Rocket.Chat to be ready
wait_for_http "$ROCKETCHAT_BASE_URL" 300

# Authenticate as admin to set initial state
echo "Authenticating as admin..."
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
  echo "ERROR: Could not authenticate as admin"
  exit 1
fi

# Ensure the initial state: 'user' role IS part of 'create-c' permission
# This guarantees the agent has work to do.
# We also include admin, bot, and app which are standard defaults.
echo "Setting initial permission state: ensuring 'user' role is in create-c..."

UPDATE_RESP=$(curl -sS -X POST \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  -H "Content-Type: application/json" \
  -d '{"permissions":[{"_id":"create-c","roles":["admin","user","bot","app"]}]}' \
  "${ROCKETCHAT_BASE_URL}/api/v1/permissions.update" 2>/dev/null || echo '{"success":false}')

# Verify the update worked
PERM_CHECK=$(curl -sS -X GET \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/permissions.listAll?updatedSince=2000-01-01T00:00:00.000Z" 2>/dev/null)

INITIAL_ROLES=$(echo "$PERM_CHECK" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('update', []):
    if p.get('_id') == 'create-c':
        print(json.dumps(p.get('roles', [])))
        sys.exit(0)
print('[]')
" 2>/dev/null || echo '[]')

echo "Initial create-c roles: $INITIAL_ROLES"
echo "$INITIAL_ROLES" > /tmp/initial_create_c_roles.json

# Launch Firefox at Rocket.Chat login page
echo "Starting Firefox with Rocket.Chat..."
restart_firefox "${ROCKETCHAT_BASE_URL}/login"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo "=== Task setup complete ==="