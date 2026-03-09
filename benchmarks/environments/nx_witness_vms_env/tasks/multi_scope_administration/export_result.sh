#!/bin/bash
echo "=== Exporting multi_scope_administration result ==="

source /workspace/scripts/task_utils.sh
refresh_nx_token > /dev/null 2>&1 || true

TASK_START=$(cat /tmp/msa_start_ts 2>/dev/null || echo "0")
PARKING_ID=$(cat /tmp/msa_parking_id 2>/dev/null || echo "")
ENTRANCE_ID=$(cat /tmp/msa_entrance_id 2>/dev/null || echo "")
SERVER_ID=$(cat /tmp/msa_server_id 2>/dev/null || echo "")

take_screenshot /tmp/multi_scope_administration_end.png

# Query system name
SYSTEM_INFO=$(nx_api_get "/rest/v1/system/info" 2>/dev/null || echo "{}")
SYSTEM_NAME=$(echo "$SYSTEM_INFO" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('name', d.get('systemName', '')))
except: print('')
" 2>/dev/null || echo "")

# Query all layouts
LAYOUTS_JSON=$(nx_api_get "/rest/v1/layouts" 2>/dev/null || echo "[]")

LAYOUT_RESULTS=$(echo "$LAYOUTS_JSON" | python3 -c "
import sys, json
try:
    layouts = json.load(sys.stdin)
    parking_id  = '${PARKING_ID}'.strip('{}')
    entrance_id = '${ENTRANCE_ID}'.strip('{}')
    server_id   = '${SERVER_ID}'.strip('{}')

    perimeter_found = False
    perimeter_has_parking = False
    perimeter_has_entrance = False
    perimeter_item_count = 0

    infra_found = False
    infra_has_server = False
    infra_item_count = 0

    for l in layouts:
        name = l.get('name','').lower()
        items = l.get('items', [])
        rids = set(item.get('resourceId','').strip('{}') for item in items)

        if 'perimeter surveillance' in name:
            perimeter_found = True
            perimeter_item_count = len(items)
            perimeter_has_parking  = parking_id in rids
            perimeter_has_entrance = entrance_id in rids

        if 'infrastructure monitoring' in name:
            infra_found = True
            infra_item_count = len(items)
            infra_has_server = server_id in rids

    print(json.dumps({
        'perimeter_found': perimeter_found,
        'perimeter_has_parking':  perimeter_has_parking,
        'perimeter_has_entrance': perimeter_has_entrance,
        'perimeter_item_count': perimeter_item_count,
        'infra_found': infra_found,
        'infra_has_server': infra_has_server,
        'infra_item_count': infra_item_count
    }))
except Exception as e:
    print(json.dumps({'perimeter_found': False, 'perimeter_has_parking': False,
                      'perimeter_has_entrance': False, 'perimeter_item_count': 0,
                      'infra_found': False, 'infra_has_server': False, 'infra_item_count': 0}))
" 2>/dev/null || echo '{"perimeter_found": false, "perimeter_has_parking": false, "perimeter_has_entrance": false, "perimeter_item_count": 0, "infra_found": false, "infra_has_server": false, "infra_item_count": 0}')

# Query vendor.tech user
USERS_JSON=$(nx_api_get "/rest/v1/users" 2>/dev/null || echo "[]")
VENDOR_INFO=$(echo "$USERS_JSON" | python3 -c "
import sys, json
try:
    users = json.load(sys.stdin)
    for u in users:
        if u.get('name','').lower() == 'vendor.tech':
            print(json.dumps({
                'exists': True,
                'email': u.get('email',''),
                'fullname': u.get('fullName','')
            }))
            break
    else:
        print(json.dumps({'exists': False, 'email': '', 'fullname': ''}))
except:
    print(json.dumps({'exists': False, 'email': '', 'fullname': ''}))
" 2>/dev/null || echo '{"exists": false, "email": "", "fullname": ""}')

cat > /tmp/multi_scope_administration_result.json << EOF
{
    "task_start": ${TASK_START},
    "system_name": "${SYSTEM_NAME}",
    "parking_lot_camera_id": "${PARKING_ID}",
    "entrance_camera_id": "${ENTRANCE_ID}",
    "server_room_camera_id": "${SERVER_ID}",
    "layout_results": ${LAYOUT_RESULTS},
    "vendor_tech_user": ${VENDOR_INFO}
}
EOF

echo "=== Export Complete ==="
cat /tmp/multi_scope_administration_result.json
