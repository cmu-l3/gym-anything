#!/bin/bash
echo "=== Exporting security configuration result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# Fetch Current State via REST API
# ============================================================

# 1. Check Role 'map_editor'
ROLE_CHECK_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -u "$GS_AUTH" "${GS_REST}/security/roles/role/map_editor" 2>/dev/null || echo "000")
ROLE_EXISTS="false"
if [ "$ROLE_CHECK_HTTP" = "200" ] || [ "$ROLE_CHECK_HTTP" = "204" ]; then
    ROLE_EXISTS="true"
fi

# 2. Check User 'editor1'
USER_JSON=$(curl -s -u "$GS_AUTH" "${GS_REST}/security/usergroup/user/editor1.json" 2>/dev/null || echo "{}")
USER_EXISTS="false"
USER_ENABLED="false"
if echo "$USER_JSON" | grep -q "\"userName\""; then
    USER_EXISTS="true"
    # Parse enabled status
    USER_ENABLED=$(echo "$USER_JSON" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('enabled', False)).lower())" 2>/dev/null || echo "false")
fi

# 3. Check Role Assignment (map_editor assigned to editor1)
USER_ROLES_JSON=$(curl -s -u "$GS_AUTH" "${GS_REST}/security/roles/user/editor1.json" 2>/dev/null || echo "{}")
ROLE_ASSIGNED="false"
# Parse roles list
ROLE_ASSIGNED=$(echo "$USER_ROLES_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    roles = d.get('roles', [])
    # GeoServer might return a list of strings or a dict wrapper depending on version/xml mapping
    # Usually ['role1', 'role2'] in JSON
    if isinstance(roles, list):
        print('true' if 'map_editor' in roles else 'false')
    else:
        print('false')
except:
    print('false')
" 2>/dev/null || echo "false")

# 4. Check Layer Access Rules (ne.*.w)
LAYERS_ACL_JSON=$(curl -s -u "$GS_AUTH" "${GS_REST}/security/acl/layers.json" 2>/dev/null || echo "{}")
# Check specific rule logic in Python
RULE_CHECK_RESULT=$(echo "$LAYERS_ACL_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Rules are keys like 'ne.*.w' -> 'role1,role2,...'
    rule_val = d.get('ne.*.w')
    if rule_val:
        roles = [r.strip() for r in rule_val.split(',')]
        has_editor = 'map_editor' in roles
        has_admin = 'ROLE_ADMINISTRATOR' in roles
        print(json.dumps({'exists': True, 'has_editor': has_editor, 'has_admin': has_admin}))
    else:
        print(json.dumps({'exists': False, 'has_editor': False, 'has_admin': False}))
except:
    print(json.dumps({'exists': False, 'has_editor': False, 'has_admin': False}))
" 2>/dev/null)

# 5. Get counts for anti-gaming comparison
FINAL_ROLES=$(curl -s -u "$GS_AUTH" "${GS_REST}/security/roles.json" 2>/dev/null || echo "{}")
FINAL_USERS=$(curl -s -u "$GS_AUTH" "${GS_REST}/security/usergroup/users.json" 2>/dev/null || echo "{}")
FINAL_ROLE_COUNT=$(echo "$FINAL_ROLES" | python3 -c "import sys, json; d=json.load(sys.stdin); rs=d.get('roles',[]); print(len(rs) if isinstance(rs, list) else 0)" 2>/dev/null || echo "0")
FINAL_USER_COUNT=$(echo "$FINAL_USERS" | python3 -c "import sys, json; d=json.load(sys.stdin); us=d.get('users',[]); print(len(us) if isinstance(us, list) else 0)" 2>/dev/null || echo "0")

INITIAL_ROLE_COUNT=$(cat /tmp/initial_role_count.txt 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")

# 6. Check GUI interaction
GUI_INTERACTION=$(check_gui_interaction)

# Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "role_exists": $ROLE_EXISTS,
    "user_exists": $USER_EXISTS,
    "user_enabled": $USER_ENABLED,
    "role_assigned": $ROLE_ASSIGNED,
    "rule_check": $RULE_CHECK_RESULT,
    "initial_role_count": $INITIAL_ROLE_COUNT,
    "final_role_count": $FINAL_ROLE_COUNT,
    "initial_user_count": $INITIAL_USER_COUNT,
    "final_user_count": $FINAL_USER_COUNT,
    "gui_interaction_detected": $GUI_INTERACTION,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/configure_security_access_result.json"

echo "=== Export complete ==="