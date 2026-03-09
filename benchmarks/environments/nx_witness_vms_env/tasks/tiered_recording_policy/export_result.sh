#!/bin/bash
echo "=== Exporting tiered_recording_policy result ==="

source /workspace/scripts/task_utils.sh
refresh_nx_token > /dev/null 2>&1 || true

TASK_START=$(cat /tmp/trp_start_ts 2>/dev/null || echo "0")
PARKING_ID=$(cat /tmp/trp_parking_id 2>/dev/null || echo "")
ENTRANCE_ID=$(cat /tmp/trp_entrance_id 2>/dev/null || echo "")
SERVER_ID=$(cat /tmp/trp_server_id 2>/dev/null || echo "")

take_screenshot /tmp/tiered_recording_policy_end.png

# Query detailed recording schedule for one camera
query_camera_schedule() {
    local cam_id="$1"
    if [ -z "$cam_id" ]; then
        echo '{"is_enabled": false, "task_count": 0, "recording_types": [], "fps_values": [], "days_covered": 0, "has_always": false, "has_motion": false}'
        return
    fi
    nx_api_get "/rest/v1/devices/${cam_id}" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    sched = d.get('schedule', {})
    is_enabled = bool(sched.get('isEnabled', False))
    tasks = sched.get('tasks', [])
    rec_types = list(set(t.get('recordingType','') for t in tasks))
    fps_vals  = list(set(t.get('fps', 0) for t in tasks))
    days = set(t.get('dayOfWeek', 0) for t in tasks if t.get('dayOfWeek', 0) > 0)
    has_always = any('always' in t.get('recordingType','').lower() for t in tasks)
    has_motion = any('low' in t.get('recordingType','').lower() or
                     'metadata' in t.get('recordingType','').lower() for t in tasks)
    print(json.dumps({
        'is_enabled': is_enabled,
        'task_count': len(tasks),
        'recording_types': rec_types,
        'fps_values': fps_vals,
        'days_covered': len(days),
        'has_always': has_always,
        'has_motion': has_motion
    }))
except Exception as e:
    print(json.dumps({'is_enabled': False, 'task_count': 0, 'recording_types': [],
                      'fps_values': [], 'days_covered': 0, 'has_always': False, 'has_motion': False}))
" 2>/dev/null
}

PARKING_SCHED=$(query_camera_schedule "$PARKING_ID")
ENTRANCE_SCHED=$(query_camera_schedule "$ENTRANCE_ID")
SERVER_SCHED=$(query_camera_schedule "$SERVER_ID")

# Check 'Security Operations Center' layout
LAYOUTS_JSON=$(nx_api_get "/rest/v1/layouts" 2>/dev/null || echo "[]")
LAYOUT_CHECK=$(echo "$LAYOUTS_JSON" | python3 -c "
import sys, json
try:
    layouts = json.load(sys.stdin)
    target_ids = set(filter(None, ['${PARKING_ID}'.strip('{}'),
                                    '${ENTRANCE_ID}'.strip('{}'),
                                    '${SERVER_ID}'.strip('{}')]))
    for l in layouts:
        if 'security operations center' in l.get('name','').lower():
            items = l.get('items', [])
            matched = sum(1 for item in items if item.get('resourceId','').strip('{}') in target_ids)
            print(json.dumps({'layout_found': True, 'item_count': len(items), 'cameras_matched': matched}))
            break
    else:
        print(json.dumps({'layout_found': False, 'item_count': 0, 'cameras_matched': 0}))
except Exception:
    print(json.dumps({'layout_found': False, 'item_count': 0, 'cameras_matched': 0}))
" 2>/dev/null || echo '{"layout_found": false, "item_count": 0, "cameras_matched": 0}')

cat > /tmp/tiered_recording_policy_result.json << EOF
{
    "task_start": ${TASK_START},
    "parking_lot_camera_id": "${PARKING_ID}",
    "entrance_camera_id": "${ENTRANCE_ID}",
    "server_room_camera_id": "${SERVER_ID}",
    "parking_lot_schedule": ${PARKING_SCHED},
    "entrance_schedule": ${ENTRANCE_SCHED},
    "server_room_schedule": ${SERVER_SCHED},
    "layout_check": ${LAYOUT_CHECK}
}
EOF

echo "=== Export Complete ==="
cat /tmp/tiered_recording_policy_result.json
