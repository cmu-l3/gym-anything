#!/bin/bash
echo "=== Exporting compile_audit_report result ==="

source /workspace/scripts/task_utils.sh

# Output paths
USER_REPORT="/home/ga/Documents/compliance_report.json"
GROUND_TRUTH_FILE="/tmp/ground_truth.json"
RESULT_JSON="/tmp/task_result.json"

# 1. Capture Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
SCREENSHOT_PATH="/tmp/task_final.png"

# Take final screenshot
take_screenshot "$SCREENSHOT_PATH"

# 2. Check User Report File Status
REPORT_EXISTS="false"
REPORT_VALID="false"
FILE_MTIME="0"

if [ -f "$USER_REPORT" ]; then
    REPORT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$USER_REPORT" 2>/dev/null || echo "0")
    
    # Check if valid JSON
    if jq empty "$USER_REPORT" >/dev/null 2>&1; then
        REPORT_VALID="true"
    fi
fi

# 3. GENERATE GROUND TRUTH (Reference Implementation)
# We run this NOW to get the exact state of the system at the end of the task.
# This ensures verification is accurate even if the system state changed slightly.

echo "Generating ground truth..."

# Get Admin Token
TOKEN=$(refresh_nx_token)

# Function to fetch and process data safely
get_ground_truth() {
    python3 -c "
import sys, json, requests, urllib3, datetime
urllib3.disable_warnings()

base = 'https://localhost:7001'
token = '$TOKEN'
headers = {'Authorization': f'Bearer {token}'}

def get(endpoint):
    try:
        r = requests.get(f'{base}{endpoint}', headers=headers, verify=False, timeout=10)
        return r.json()
    except:
        return []

def get_info(endpoint):
    try:
        r = requests.get(f'{base}{endpoint}', headers=headers, verify=False, timeout=10)
        return r.json()
    except:
        return {}

try:
    # 1. System Info
    info = get_info('/rest/v1/system/info')
    
    # 2. Servers
    servers = get('/rest/v1/servers')
    
    # 3. Devices (Cameras)
    devices = get('/rest/v1/devices')
    cameras_list = []
    online_count = 0
    for d in devices:
        cameras_list.append({'name': d.get('name'), 'id': d.get('id')})
        if d.get('status') == 'Online':
            online_count += 1
            
    # 4. Users
    users = get('/rest/v1/users')
    users_list = []
    enabled_count = 0
    for u in users:
        users_list.append({'name': u.get('name'), 'email': u.get('email', '')})
        if u.get('isEnabled', True):
            enabled_count += 1
            
    # 5. Layouts
    layouts = get('/rest/v1/layouts')
    
    # 6. Event Rules
    # Note: Endpoint might vary by version, checking standard one
    rules = get('/rest/v1/eventRules')
    if isinstance(rules, dict) and 'reply' in rules: # Sometimes wrapped
        rules = rules['reply']
    
    gt = {
        'system_name': info.get('systemName', ''),
        'system_version': info.get('version', ''),
        'server_count': len(servers) if isinstance(servers, list) else 0,
        'total_cameras': len(devices) if isinstance(devices, list) else 0,
        'cameras': cameras_list,
        'total_users': len(users) if isinstance(users, list) else 0,
        'users': users_list,
        'total_layouts': len(layouts) if isinstance(layouts, list) else 0,
        'total_event_rules': len(rules) if isinstance(rules, list) else 0,
        'compliance_summary': {
            'cameras_online': online_count,
            'users_enabled': enabled_count
        }
    }
    print(json.dumps(gt))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$GROUND_TRUTH_FILE"
}

get_ground_truth

# 4. Package everything into result JSON
# We include metadata about the user file and the path to the ground truth
# (Verifier will load the actual content)

cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_valid_json": $REPORT_VALID,
    "report_mtime": $FILE_MTIME,
    "user_report_path": "$USER_REPORT",
    "ground_truth_path": "$GROUND_TRUTH_FILE",
    "screenshot_path": "$SCREENSHOT_PATH"
}
EOF

# Ensure permissions
chmod 644 "$RESULT_JSON" "$GROUND_TRUTH_FILE" 2>/dev/null || true
if [ -f "$USER_REPORT" ]; then
    chmod 644 "$USER_REPORT" 2>/dev/null || true
fi

echo "Export complete. Result at $RESULT_JSON"