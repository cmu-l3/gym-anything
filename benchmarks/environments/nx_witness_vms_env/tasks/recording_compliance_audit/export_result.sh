#!/bin/bash
echo "=== Exporting recording_compliance_audit result ==="

source /workspace/scripts/task_utils.sh
refresh_nx_token > /dev/null 2>&1 || true

# Read saved camera IDs
PARKING_ID=$(cat /tmp/rca_parking_id 2>/dev/null || echo "")
SERVER_ID=$(cat /tmp/rca_server_id 2>/dev/null || echo "")
ENTRANCE_ID=$(cat /tmp/rca_entrance_id 2>/dev/null || echo "")
TASK_START=$(cat /tmp/recording_compliance_audit_start_ts 2>/dev/null || echo "0")
INITIAL_LAYOUT_COUNT=$(cat /tmp/rca_initial_layout_count 2>/dev/null || echo "0")

take_screenshot /tmp/recording_compliance_audit_end.png

# Query recording schedule state for one camera (returns JSON)
check_camera_recording() {
    local cam_id="$1"
    if [ -z "$cam_id" ]; then
        echo '{"is_enabled": false, "task_count": 0, "has_always_type": false, "days_covered": 0, "found": false}'
        return
    fi
    nx_api_get "/rest/v1/devices/${cam_id}" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    sched = d.get('schedule', {})
    is_enabled = bool(sched.get('isEnabled', False))
    tasks = sched.get('tasks', [])
    has_always = any(t.get('recordingType','') == 'always' for t in tasks)
    days = set(t.get('dayOfWeek', 0) for t in tasks if t.get('dayOfWeek', 0) > 0)
    print(json.dumps({
        'is_enabled': is_enabled,
        'task_count': len(tasks),
        'has_always_type': has_always,
        'days_covered': len(days),
        'found': True
    }))
except Exception as e:
    print(json.dumps({'is_enabled': False, 'task_count': 0, 'has_always_type': False, 'days_covered': 0, 'found': False}))
" 2>/dev/null || echo '{"is_enabled": false, "task_count": 0, "has_always_type": false, "days_covered": 0, "found": false}'
}

PARKING_STATUS=$(check_camera_recording "$PARKING_ID")
SERVER_STATUS=$(check_camera_recording "$SERVER_ID")
ENTRANCE_STATUS=$(check_camera_recording "$ENTRANCE_ID")

# Check for 'Compliance Audit View' layout and its camera contents
LAYOUTS_JSON=$(nx_api_get "/rest/v1/layouts" 2>/dev/null || echo "[]")

LAYOUT_CHECK=$(echo "$LAYOUTS_JSON" | python3 -c "
import sys, json
try:
    layouts = json.load(sys.stdin)
    target_ids = set(filter(None, ['${PARKING_ID}'.strip('{}'), '${SERVER_ID}'.strip('{}'), '${ENTRANCE_ID}'.strip('{}')]))
    for l in layouts:
        if l.get('name','').strip().lower() == 'compliance audit view':
            items = l.get('items', [])
            matched = 0
            for item in items:
                rid = item.get('resourceId', '').strip('{}')
                if rid in target_ids:
                    matched += 1
            print(json.dumps({'layout_found': True, 'item_count': len(items), 'cameras_matched': matched}))
            break
    else:
        print(json.dumps({'layout_found': False, 'item_count': 0, 'cameras_matched': 0}))
except Exception as e:
    print(json.dumps({'layout_found': False, 'item_count': 0, 'cameras_matched': 0}))
" 2>/dev/null || echo '{"layout_found": false, "item_count": 0, "cameras_matched": 0}')

TOTAL_CAMERAS=$(echo "$PARKING_ID $SERVER_ID $ENTRANCE_ID" | tr ' ' '\n' | grep -vc '^$' 2>/dev/null || echo "3")

cat > /tmp/recording_compliance_audit_result.json << EOF
{
    "task_start": ${TASK_START},
    "parking_lot_camera_id": "${PARKING_ID}",
    "server_room_camera_id": "${SERVER_ID}",
    "entrance_camera_id": "${ENTRANCE_ID}",
    "initial_layout_count": ${INITIAL_LAYOUT_COUNT},
    "total_cameras": ${TOTAL_CAMERAS},
    "parking_lot_recording": ${PARKING_STATUS},
    "server_room_recording": ${SERVER_STATUS},
    "entrance_camera_recording": ${ENTRANCE_STATUS},
    "layout_check": ${LAYOUT_CHECK}
}
EOF

echo "=== Export Complete ==="
echo "Result:"
cat /tmp/recording_compliance_audit_result.json
