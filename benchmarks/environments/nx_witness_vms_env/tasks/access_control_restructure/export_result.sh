#!/bin/bash
echo "=== Exporting access_control_restructure result ==="

source /workspace/scripts/task_utils.sh
refresh_nx_token > /dev/null 2>&1 || true

TASK_START=$(cat /tmp/acr_start_ts 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/acr_initial_user_count 2>/dev/null || echo "0")
ENTRANCE_ID=$(cat /tmp/acr_entrance_id 2>/dev/null || echo "")
SERVER_ID=$(cat /tmp/acr_server_id 2>/dev/null || echo "")

take_screenshot /tmp/access_control_restructure_end.png

# Query all users
USERS_JSON=$(nx_api_get "/rest/v1/users" 2>/dev/null || echo "[]")

USER_CHECK=$(echo "$USERS_JSON" | python3 -c "
import sys, json
try:
    users = json.load(sys.stdin)
    names = [u.get('name','').lower() for u in users]
    john_exists  = 'john.smith' in names
    sarah_exists = 'sarah.jones' in names
    ext_user = None
    for u in users:
        if u.get('name','').lower() == 'ext.auditor':
            ext_user = u
            break
    ext_exists   = ext_user is not None
    ext_email    = ext_user.get('email','') if ext_user else ''
    ext_fullname = ext_user.get('fullName','') if ext_user else ''
    print(json.dumps({
        'john_smith_exists':  john_exists,
        'sarah_jones_exists': sarah_exists,
        'ext_auditor_exists': ext_exists,
        'ext_auditor_email':  ext_email,
        'ext_auditor_fullname': ext_fullname,
        'total_users': len(users)
    }))
except Exception as e:
    print(json.dumps({
        'john_smith_exists': True, 'sarah_jones_exists': True,
        'ext_auditor_exists': False, 'ext_auditor_email': '',
        'ext_auditor_fullname': '', 'total_users': 0
    }))
" 2>/dev/null || echo '{"john_smith_exists": true, "sarah_jones_exists": true, "ext_auditor_exists": false, "ext_auditor_email": "", "ext_auditor_fullname": "", "total_users": 0}')

# Query layouts for 'Audit Trail View'
LAYOUTS_JSON=$(nx_api_get "/rest/v1/layouts" 2>/dev/null || echo "[]")

LAYOUT_CHECK=$(echo "$LAYOUTS_JSON" | python3 -c "
import sys, json
try:
    layouts = json.load(sys.stdin)
    target_ids = set(filter(None, ['${ENTRANCE_ID}'.strip('{}'), '${SERVER_ID}'.strip('{}')]))
    for l in layouts:
        if l.get('name','').strip().lower() == 'audit trail view':
            items = l.get('items', [])
            matched = 0
            for item in items:
                rid = item.get('resourceId','').strip('{}')
                if rid in target_ids:
                    matched += 1
            print(json.dumps({'layout_found': True, 'item_count': len(items), 'cameras_matched': matched}))
            break
    else:
        print(json.dumps({'layout_found': False, 'item_count': 0, 'cameras_matched': 0}))
except Exception as e:
    print(json.dumps({'layout_found': False, 'item_count': 0, 'cameras_matched': 0}))
" 2>/dev/null || echo '{"layout_found": false, "item_count": 0, "cameras_matched": 0}')

cat > /tmp/access_control_restructure_result.json << EOF
{
    "task_start": ${TASK_START},
    "initial_user_count": ${INITIAL_USER_COUNT},
    "entrance_camera_id": "${ENTRANCE_ID}",
    "server_camera_id": "${SERVER_ID}",
    "user_check": ${USER_CHECK},
    "layout_check": ${LAYOUT_CHECK}
}
EOF

echo "=== Export Complete ==="
echo "Result:"
cat /tmp/access_control_restructure_result.json
