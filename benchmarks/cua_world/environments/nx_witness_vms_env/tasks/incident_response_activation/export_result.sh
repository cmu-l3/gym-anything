#!/bin/bash
echo "=== Exporting incident_response_activation Result ==="
source /workspace/scripts/task_utils.sh

refresh_nx_token > /dev/null 2>&1 || true
take_screenshot "/tmp/ira_final_screenshot.png"

# Load camera IDs if available
if [ -f /tmp/ira_camera_ids.sh ]; then
    source /tmp/ira_camera_ids.sh
fi

# ---- Check recording state for each camera ----
CAMERAS_JSON=$(nx_api_get "/rest/v1/devices?type=Camera" 2>/dev/null || echo "[]")

check_camera_recording() {
    local cam_id="$1"
    if [ -z "$cam_id" ]; then
        echo '{"found": false, "is_enabled": false, "task_count": 0, "has_always": false, "days_covered": 0}'
        return
    fi
    echo "$CAMERAS_JSON" | python3 -c "
import json, sys
cam_id = '$cam_id'.strip('{}')
try:
    devices = json.load(sys.stdin)
    cam = next((d for d in devices if d['id'].strip('{}') == cam_id), None)
    if not cam:
        print(json.dumps({'found': False, 'is_enabled': False, 'task_count': 0, 'has_always': False, 'days_covered': 0}))
        sys.exit(0)
    sched = cam.get('schedule', {})
    is_enabled = bool(sched.get('isEnabled', False))
    tasks = sched.get('tasks', [])
    has_always = any(t.get('recordingType','') == 'always' for t in tasks)
    days_covered = len({t.get('dayOfWeek') for t in tasks if t.get('recordingType','') == 'always'})
    print(json.dumps({'found': True, 'name': cam.get('name',''), 'is_enabled': is_enabled,
                      'task_count': len(tasks), 'has_always': has_always, 'days_covered': days_covered}))
except Exception as e:
    print(json.dumps({'found': False, 'is_enabled': False, 'task_count': 0, 'has_always': False, 'days_covered': 0}))
" 2>/dev/null || echo '{"found": false, "is_enabled": false, "task_count": 0, "has_always": false, "days_covered": 0}'
}

PARKING_RESULT=$(check_camera_recording "${PARKING_CAM_ID:-}")
ENTRANCE_RESULT=$(check_camera_recording "${ENTRANCE_CAM_ID:-}")
SERVER_RESULT=$(check_camera_recording "${SERVER_CAM_ID:-}")

echo "Parking Lot Camera: $PARKING_RESULT"
echo "Entrance Camera: $ENTRANCE_RESULT"
echo "Server Room Camera: $SERVER_RESULT"

# Save to temp files for safe Python assembly (remove first in case owned by root from prior run)
rm -f /tmp/ira_parking.json /tmp/ira_entrance.json /tmp/ira_server.json \
      /tmp/ira_sec_op.json /tmp/ira_icmdr.json /tmp/ira_icc.json \
      /tmp/ira_layout_cams.json /tmp/incident_response_activation_result.json 2>/dev/null || true
echo "$PARKING_RESULT" > /tmp/ira_parking.json
echo "$ENTRANCE_RESULT" > /tmp/ira_entrance.json
echo "$SERVER_RESULT" > /tmp/ira_server.json

# ---- Check security.operator user updates ----
USERS=$(nx_api_get "/rest/v1/users" 2>/dev/null || echo "[]")

echo "$USERS" | python3 -c "
import json, sys
try:
    users = json.load(sys.stdin)
    u = next((u for u in users if u.get('name','').lower() == 'security.operator'), None)
    if not u:
        print(json.dumps({'exists': False}))
    else:
        print(json.dumps({
            'exists': True,
            'id': u.get('id',''),
            'fullname': u.get('fullName', u.get('full_name', '')),
            'email': u.get('email','')
        }))
except:
    print(json.dumps({'exists': False}))
" 2>/dev/null > /tmp/ira_sec_op.json || echo '{"exists": false}' > /tmp/ira_sec_op.json

SEC_OP_DATA=$(cat /tmp/ira_sec_op.json)
echo "security.operator: $SEC_OP_DATA"

# ---- Check incident.cmdr user creation ----
echo "$USERS" | python3 -c "
import json, sys
try:
    users = json.load(sys.stdin)
    u = next((u for u in users if u.get('name','').lower() == 'incident.cmdr'), None)
    if not u:
        print(json.dumps({'exists': False}))
    else:
        print(json.dumps({
            'exists': True,
            'id': u.get('id',''),
            'fullname': u.get('fullName', u.get('full_name', '')),
            'email': u.get('email',''),
            'permissions': u.get('permissions', u.get('role',''))
        }))
except:
    print(json.dumps({'exists': False}))
" 2>/dev/null > /tmp/ira_icmdr.json || echo '{"exists": false}' > /tmp/ira_icmdr.json

ICMDR_DATA=$(cat /tmp/ira_icmdr.json)
echo "incident.cmdr: $ICMDR_DATA"

# ---- Check 'Incident Command Center' layout ----
LAYOUTS=$(nx_api_get "/rest/v1/layouts" 2>/dev/null || echo "[]")

echo "$LAYOUTS" | python3 -c "
import json, sys
try:
    layouts = json.load(sys.stdin)
    layout = next((l for l in layouts if l.get('name','').lower() == 'incident command center'), None)
    if not layout:
        print(json.dumps({'found': False}))
        sys.exit(0)
    items = layout.get('items', [])
    resource_ids = [item.get('resourceId','').strip('{}') for item in items if item.get('resourceId','').strip('{}')]
    print(json.dumps({'found': True, 'id': layout.get('id',''), 'name': layout.get('name',''),
                      'item_count': len(items), 'resource_ids': resource_ids}))
except:
    print(json.dumps({'found': False}))
" 2>/dev/null > /tmp/ira_icc.json || echo '{"found": false}' > /tmp/ira_icc.json

ICC_DATA=$(cat /tmp/ira_icc.json)
echo "Incident Command Center layout: $ICC_DATA"

# ---- Match layout cameras ----
python3 << 'PYEOF'
import json

try:
    with open('/tmp/ira_icc.json') as f: icc = json.load(f)
    with open('/tmp/ira_camera_ids.sh') as f:
        ids = {}
        for line in f:
            line = line.strip()
            if '=' in line:
                k, v = line.split('=', 1)
                ids[k] = v.strip('{}')
    parking_id = ids.get('PARKING_CAM_ID', '').strip('{}')
    entrance_id = ids.get('ENTRANCE_CAM_ID', '').strip('{}')
    server_id = ids.get('SERVER_CAM_ID', '').strip('{}')
    resource_ids = [r.strip('{}') for r in icc.get('resource_ids', [])]
    has_parking = bool(parking_id and parking_id in resource_ids)
    has_entrance = bool(entrance_id and entrance_id in resource_ids)
    has_server = bool(server_id and server_id in resource_ids)
    result = {'has_parking': has_parking, 'has_entrance': has_entrance,
              'has_server': has_server, 'camera_count_in_layout': len(resource_ids)}
except Exception as e:
    result = {'has_parking': False, 'has_entrance': False, 'has_server': False, 'camera_count_in_layout': 0}

with open('/tmp/ira_layout_cams.json', 'w') as f:
    json.dump(result, f)
print(json.dumps(result))
PYEOF

LAYOUT_CAMS=$(cat /tmp/ira_layout_cams.json 2>/dev/null || echo '{"has_parking":false,"has_entrance":false,"has_server":false,"camera_count_in_layout":0}')
echo "Layout camera matches: $LAYOUT_CAMS"

# ---- Assemble final JSON from files ----
python3 << 'PYEOF'
import json

def load_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return default or {}

parking = load_json('/tmp/ira_parking.json', {'found': False, 'is_enabled': False, 'task_count': 0, 'has_always': False, 'days_covered': 0})
entrance = load_json('/tmp/ira_entrance.json', {'found': False, 'is_enabled': False, 'task_count': 0, 'has_always': False, 'days_covered': 0})
server = load_json('/tmp/ira_server.json', {'found': False, 'is_enabled': False, 'task_count': 0, 'has_always': False, 'days_covered': 0})
sec_op = load_json('/tmp/ira_sec_op.json', {'exists': False})
icmdr = load_json('/tmp/ira_icmdr.json', {'exists': False})
icc = load_json('/tmp/ira_icc.json', {'found': False})
layout_cams = load_json('/tmp/ira_layout_cams.json', {'has_parking': False, 'has_entrance': False, 'has_server': False, 'camera_count_in_layout': 0})

result = {
    'cameras': {'parking': parking, 'entrance': entrance, 'server': server},
    'security_operator': sec_op,
    'incident_commander': icmdr,
    'incident_command_center': icc,
    'layout_cameras': layout_cams
}

with open('/tmp/incident_response_activation_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print('Result written to /tmp/incident_response_activation_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
