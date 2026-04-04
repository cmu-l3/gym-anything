#!/bin/bash
# Export script for User Account Setup task

echo "=== Exporting User Account Setup Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

echo "Looking up user fatmata.koroma via DHIS2 API..."

# Query for the specific user
USER_RESULT=$(dhis2_api "users?filter=username:eq:fatmata.koroma&fields=id,username,firstName,surname,email,disabled,userRoles[id,displayName],organisationUnits[id,displayName],dataViewOrganisationUnits[id,displayName],teiSearchOrganisationUnits[id,displayName]&paging=false" 2>/dev/null)

echo "API response received, parsing..."

USER_DATA=$(echo "$USER_RESULT" | python3 -c "
import json, sys

try:
    data = json.load(sys.stdin)
    users = data.get('users', [])
    if not users:
        print(json.dumps({
            'user_found': False,
            'username': '',
            'first_name': '',
            'surname': '',
            'email': '',
            'disabled': True,
            'role_count': 0,
            'roles': [],
            'capture_org_unit_count': 0,
            'capture_org_units': [],
            'view_org_unit_count': 0,
            'view_org_units': []
        }))
    else:
        u = users[0]
        roles = u.get('userRoles', [])
        capture_ous = u.get('organisationUnits', [])
        view_ous = u.get('dataViewOrganisationUnits', []) or u.get('teiSearchOrganisationUnits', [])
        print(json.dumps({
            'user_found': True,
            'user_id': u.get('id', ''),
            'username': u.get('username', ''),
            'first_name': u.get('firstName', ''),
            'surname': u.get('surname', ''),
            'email': u.get('email', ''),
            'disabled': u.get('disabled', False),
            'role_count': len(roles),
            'roles': [r.get('displayName', '') for r in roles],
            'capture_org_unit_count': len(capture_ous),
            'capture_org_units': [o.get('displayName', '') for o in capture_ous],
            'view_org_unit_count': len(view_ous),
            'view_org_units': [o.get('displayName', '') for o in view_ous]
        }))
except Exception as e:
    print(json.dumps({'user_found': False, 'error': str(e)}))
" 2>/dev/null || echo '{"user_found": false}')

echo "User data:"
echo "$USER_DATA" | python3 -m json.tool 2>/dev/null || echo "$USER_DATA"

# Extract key fields
USER_FOUND=$(echo "$USER_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('user_found', False)).lower())" 2>/dev/null || echo "false")
USER_FNAME=$(echo "$USER_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('first_name',''))" 2>/dev/null || echo "")
USER_SURNAME=$(echo "$USER_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('surname',''))" 2>/dev/null || echo "")
USER_EMAIL=$(echo "$USER_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('email',''))" 2>/dev/null || echo "")
USER_DISABLED=$(echo "$USER_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('disabled', True)).lower())" 2>/dev/null || echo "true")
ROLE_COUNT=$(echo "$USER_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('role_count', 0))" 2>/dev/null || echo "0")
CAPTURE_OU_COUNT=$(echo "$USER_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('capture_org_unit_count', 0))" 2>/dev/null || echo "0")

echo "User found: $USER_FOUND"
echo "  Name: $USER_FNAME $USER_SURNAME"
echo "  Email: $USER_EMAIL"
echo "  Disabled: $USER_DISABLED"
echo "  Roles: $ROLE_COUNT"
echo "  Capture org units: $CAPTURE_OU_COUNT"

# Write result JSON
cat > /tmp/user_account_setup_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "user_found": $USER_FOUND,
    "user_details": $USER_DATA,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/user_account_setup_result.json 2>/dev/null || true
echo ""
echo "Result JSON saved to /tmp/user_account_setup_result.json"
cat /tmp/user_account_setup_result.json
echo ""
echo "=== Export Complete ==="
