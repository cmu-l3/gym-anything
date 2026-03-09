#!/bin/bash
# Export script for access_control_configuration task

echo "=== Exporting access_control_configuration Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/access_control_configuration_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULT_NONCE=$(get_result_nonce)
GUI_INTERACTION=$(check_gui_interaction)

# ----- Check user gis_reader -----
USERS_JSON=$(curl -s -u "admin:Admin123!" \
    "http://localhost:8080/geoserver/rest/security/usergroup/users.json" 2>/dev/null || echo "{}")

USER_FOUND=$(echo "$USERS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
users = d.get('users', {}).get('user', [])
if not isinstance(users, list): users = [users] if users else []
names = [u.get('userName','') for u in users]
print('true' if 'gis_reader' in names else 'false')
" 2>/dev/null || echo "false")

# ----- Check role ROLE_GIS_READER -----
ROLES_JSON=$(curl -s -u "admin:Admin123!" \
    "http://localhost:8080/geoserver/rest/security/roles.json" 2>/dev/null || echo "{}")

ROLE_FOUND=$(echo "$ROLES_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
roles = d.get('roles', {}).get('role', [])
if not isinstance(roles, list): roles = [roles] if roles else []
print('true' if 'ROLE_GIS_READER' in roles else 'false')
" 2>/dev/null || echo "false")

# ----- Check role assignment for gis_reader -----
USER_ROLES_JSON=$(curl -s -u "admin:Admin123!" \
    "http://localhost:8080/geoserver/rest/security/usergroup/user/gis_reader/roles.json" \
    2>/dev/null || echo "{}")

ROLE_ASSIGNED=$(echo "$USER_ROLES_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
roles = d.get('roles', {}).get('role', [])
if not isinstance(roles, list): roles = [roles] if roles else []
print('true' if 'ROLE_GIS_READER' in roles else 'false')
" 2>/dev/null || echo "false")

# ----- Check data access rules for ne.* -----
ACL_JSON=$(curl -s -u "admin:Admin123!" \
    "http://localhost:8080/geoserver/rest/security/acl/layers.json" 2>/dev/null || echo "{}")

DATA_RULE_FOUND=$(echo "$ACL_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
# ACL returns dict: {rule_key: 'ROLE1,ROLE2', ...}
# Look for a rule matching ne.* with ROLE_GIS_READER
for key, val in d.items():
    if key.startswith('ne.') and 'ROLE_GIS_READER' in str(val):
        print('true')
        break
else:
    print('false')
" 2>/dev/null || echo "false")

DATA_RULE_KEY=$(echo "$ACL_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for key, val in d.items():
    if key.startswith('ne.') and 'ROLE_GIS_READER' in str(val):
        print(key)
        break
" 2>/dev/null || echo "")

DATA_RULE_VALUE=$(echo "$ACL_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for key, val in d.items():
    if key.startswith('ne.') and 'ROLE_GIS_READER' in str(val):
        print(val)
        break
" 2>/dev/null || echo "")

# Also check if there are ANY data rules with ROLE_GIS_READER (more flexible match)
DATA_RULE_ANY=$(echo "$ACL_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for key, val in d.items():
    if 'ROLE_GIS_READER' in str(val):
        print(key + ' -> ' + str(val))
        break
" 2>/dev/null || echo "")

# ----- Check service security rules for WMS -----
SVC_JSON=$(curl -s -u "admin:Admin123!" \
    "http://localhost:8080/geoserver/rest/security/acl/services.json" 2>/dev/null || echo "{}")

SERVICE_RULE_FOUND=$(echo "$SVC_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
# Service ACL: {service_key: 'ROLE1,ROLE2', ...}
for key, val in d.items():
    if 'wms' in key.lower() and ('ROLE_GIS_READER' in str(val) or 'ANONYMOUS' in str(val)):
        print('true')
        break
else:
    # Check if any WMS rule exists at all (even if different roles)
    for key in d.keys():
        if 'wms' in key.lower():
            print('partial')
            break
    else:
        print('false')
" 2>/dev/null || echo "false")

SERVICE_RULE_VALUE=$(echo "$SVC_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for key, val in d.items():
    if 'wms' in key.lower():
        print(key + ':' + str(val))
        break
" 2>/dev/null || echo "")

CURRENT_USER_COUNT=$(echo "$USERS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
users = d.get('users', {}).get('user', [])
if not isinstance(users, list): users = [users] if users else []
print(len(users))
" 2>/dev/null || echo "0")

TMPFILE=$(mktemp /tmp/access_control_configuration_result_XXXXXX.json)
python3 << PYEOF
import json

result = {
    "result_nonce": "${RESULT_NONCE}",
    "task_start": ${TASK_START},
    "gui_interaction_detected": $([ "$GUI_INTERACTION" = "true" ] && echo "True" || echo "False"),

    "user_found": $([ "$USER_FOUND" = "true" ] && echo "True" || echo "False"),
    "role_found": $([ "$ROLE_FOUND" = "true" ] && echo "True" || echo "False"),
    "role_assigned": $([ "$ROLE_ASSIGNED" = "true" ] && echo "True" || echo "False"),

    "data_rule_found": $([ "$DATA_RULE_FOUND" = "true" ] && echo "True" || echo "False"),
    "data_rule_key": "${DATA_RULE_KEY}",
    "data_rule_value": "${DATA_RULE_VALUE}",
    "data_rule_any": "${DATA_RULE_ANY}",

    "service_rule_found": $([ "$SERVICE_RULE_FOUND" = "true" ] && echo "True" || echo "False"),
    "service_rule_partial": $([ "$SERVICE_RULE_FOUND" = "partial" ] && echo "True" || echo "False"),
    "service_rule_value": "${SERVICE_RULE_VALUE}",

    "initial_user_count": $(cat /tmp/initial_user_count 2>/dev/null || echo "0"),
    "current_user_count": ${CURRENT_USER_COUNT}
}

with open("${TMPFILE}", "w") as f:
    json.dump(result, f, indent=2)
print("Result written")
PYEOF

safe_write_result "$TMPFILE" "/tmp/access_control_configuration_result.json"

echo "=== Export Complete ==="
