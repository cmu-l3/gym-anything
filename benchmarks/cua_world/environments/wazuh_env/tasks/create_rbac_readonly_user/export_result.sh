#!/bin/bash
set -e
echo "=== Exporting RBAC task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TOKEN=$(get_api_token)

# Helper to check JSON output safely
check_json_field() {
    echo "$1" | python3 -c "import sys, json; print(json.load(sys.stdin)$2)" 2>/dev/null || echo ""
}

# 1. Verify Policy
echo "Verifying Policy..."
POLICY_RES=$(curl -sk -X GET "${WAZUH_API_URL}/security/policies?search=readonly_agents" -H "Authorization: Bearer ${TOKEN}")
POLICY_ID=$(check_json_field "$POLICY_RES" ".get('data',{}).get('affected_items',[{}])[0].get('id','')")
POLICY_EXISTS="false"
POLICY_CORRECT="false"

if [ -n "$POLICY_ID" ]; then
    POLICY_EXISTS="true"
    # Get full policy details to check actions
    POLICY_DETAIL=$(curl -sk -X GET "${WAZUH_API_URL}/security/policies/${POLICY_ID}" -H "Authorization: Bearer ${TOKEN}")
    # Verify content
    POLICY_CORRECT=$(echo "$POLICY_DETAIL" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('affected_items', [])
if items:
    pol = items[0].get('policy', {})
    actions = set(pol.get('actions', []))
    resources = set(pol.get('resources', []))
    effect = pol.get('effect', '')
    req_actions = {'agent:read', 'group:read'}
    req_resources = {'agent:id:*', 'group:id:*'}
    if req_actions.issubset(actions) and req_resources.issubset(resources) and effect == 'allow':
        print('true')
    else:
        print('false')
else:
    print('false')
")
fi

# 2. Verify Role & Linkage
echo "Verifying Role..."
ROLE_RES=$(curl -sk -X GET "${WAZUH_API_URL}/security/roles?search=soc_analyst_readonly" -H "Authorization: Bearer ${TOKEN}")
ROLE_ID=$(check_json_field "$ROLE_RES" ".get('data',{}).get('affected_items',[{}])[0].get('id','')")
ROLE_EXISTS="false"
POLICY_LINKED="false"

if [ -n "$ROLE_ID" ]; then
    ROLE_EXISTS="true"
    # Check if policy is linked to this role
    ROLE_POLICIES=$(curl -sk -X GET "${WAZUH_API_URL}/security/roles/${ROLE_ID}" -H "Authorization: Bearer ${TOKEN}")
    # Look for readonly_agents in the policies list of the role
    POLICY_LINKED=$(echo "$ROLE_POLICIES" | grep -q "readonly_agents" && echo "true" || echo "false")
fi

# 3. Verify User & Linkage
echo "Verifying User..."
USER_RES=$(curl -sk -X GET "${WAZUH_API_URL}/security/users?search=analyst_jsmith" -H "Authorization: Bearer ${TOKEN}")
USER_ID=$(check_json_field "$USER_RES" ".get('data',{}).get('affected_items',[{}])[0].get('id','')")
USER_EXISTS="false"
ROLE_ASSIGNED="false"

if [ -n "$USER_ID" ]; then
    USER_EXISTS="true"
    # Check if role is assigned to user
    USER_ROLES=$(curl -sk -X GET "${WAZUH_API_URL}/security/users/${USER_ID}" -H "Authorization: Bearer ${TOKEN}")
    ROLE_ASSIGNED=$(echo "$USER_ROLES" | grep -q "soc_analyst_readonly" && echo "true" || echo "false")
fi

# 4. Verify Authentication (Anti-gaming: user must actually work)
echo "Verifying Authentication..."
AUTH_TEST=$(curl -sk -X POST "${WAZUH_API_URL}/security/user/authenticate" -u "analyst_jsmith:S0cAn4lyst!2024")
AUTH_SUCCESS=$(echo "$AUTH_TEST" | grep -q "token" && echo "true" || echo "false")

# 5. Check Verification File
FILE_EXISTS="false"
if [ -f "/home/ga/rbac_verification.json" ] && [ -s "/home/ga/rbac_verification.json" ]; then
    FILE_EXISTS="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "policy_exists": $POLICY_EXISTS,
    "policy_correct": $POLICY_CORRECT,
    "role_exists": $ROLE_EXISTS,
    "policy_linked_to_role": $POLICY_LINKED,
    "user_exists": $USER_EXISTS,
    "role_assigned_to_user": $ROLE_ASSIGNED,
    "authentication_success": $AUTH_SUCCESS,
    "verification_file_exists": $FILE_EXISTS,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json