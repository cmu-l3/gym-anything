#!/bin/bash
set -e
echo "=== Setting up RBAC user creation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Wazuh API to be ready
echo "Waiting for Wazuh API..."
wait_for_service "Wazuh API" "curl -sk -u '${WAZUH_API_USER}:${WAZUH_API_PASS}' ${WAZUH_API_URL}/ | grep -q Wazuh" 180

# Get Admin Token for cleanup
TOKEN=$(get_api_token)

# --- Cleanup: Remove artifacts from previous runs ---
echo "Cleaning up previous RBAC objects..."

# Delete User if exists
USER_ID=$(curl -sk -X GET "${WAZUH_API_URL}/security/users?search=analyst_jsmith" -H "Authorization: Bearer ${TOKEN}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('data',{}).get('affected_items',[{}])[0].get('id',''))" 2>/dev/null || true)
if [ -n "$USER_ID" ]; then
    curl -sk -X DELETE "${WAZUH_API_URL}/security/users?user_ids=${USER_ID}" -H "Authorization: Bearer ${TOKEN}" >/dev/null
    echo "Removed existing user analyst_jsmith"
fi

# Delete Role if exists
ROLE_ID=$(curl -sk -X GET "${WAZUH_API_URL}/security/roles?search=soc_analyst_readonly" -H "Authorization: Bearer ${TOKEN}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('data',{}).get('affected_items',[{}])[0].get('id',''))" 2>/dev/null || true)
if [ -n "$ROLE_ID" ]; then
    curl -sk -X DELETE "${WAZUH_API_URL}/security/roles?role_ids=${ROLE_ID}" -H "Authorization: Bearer ${TOKEN}" >/dev/null
    echo "Removed existing role soc_analyst_readonly"
fi

# Delete Policy if exists
POLICY_ID=$(curl -sk -X GET "${WAZUH_API_URL}/security/policies?search=readonly_agents" -H "Authorization: Bearer ${TOKEN}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('data',{}).get('affected_items',[{}])[0].get('id',''))" 2>/dev/null || true)
if [ -n "$POLICY_ID" ]; then
    curl -sk -X DELETE "${WAZUH_API_URL}/security/policies?policy_ids=${POLICY_ID}" -H "Authorization: Bearer ${TOKEN}" >/dev/null
    echo "Removed existing policy readonly_agents"
fi

rm -f /home/ga/rbac_verification.json 2>/dev/null || true

# Record initial counts (should be baseline)
INITIAL_USERS=$(curl -sk -X GET "${WAZUH_API_URL}/security/users" -H "Authorization: Bearer ${TOKEN}" | jq '.data.total_affected_items')
echo "$INITIAL_USERS" > /tmp/initial_user_count.txt

# Open a terminal for the agent to work in
echo "Launching terminal..."
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize --working-directory=/home/ga &"
    sleep 3
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== RBAC task setup complete ==="