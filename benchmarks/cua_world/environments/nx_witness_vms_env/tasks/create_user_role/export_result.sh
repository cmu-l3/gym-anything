#!/bin/bash
set -e
echo "=== Exporting create_user_role results ==="

source /workspace/scripts/task_utils.sh

# Refresh token just in case
refresh_nx_token > /dev/null

# Get Ground Truth IDs
PARKING_ID=$(cat /tmp/task_ground_truth/parking_id 2>/dev/null || echo "")
ENTRANCE_ID=$(cat /tmp/task_ground_truth/entrance_id 2>/dev/null || echo "")
INITIAL_COUNT=$(cat /tmp/initial_role_count.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Fetch all roles
ROLES_JSON=$(nx_api_get "/rest/v1/userRoles")

# Fetch specific role if it exists
TARGET_ROLE=$(echo "$ROLES_JSON" | python3 -c "
import sys, json
try:
    roles = json.load(sys.stdin)
    found = {}
    for r in roles:
        if r.get('name', '') == 'Night Shift Monitor':
            found = r
            break
    print(json.dumps(found))
except:
    print('{}')
" 2>/dev/null)

# Calculate final count
FINAL_COUNT=$(echo "$ROLES_JSON" | python3 -c "
import sys, json
try:
    roles = json.load(sys.stdin)
    print(len(roles) if isinstance(roles, list) else 0)
except:
    print(0)
" 2>/dev/null)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_role_count': int('$INITIAL_COUNT'),
    'final_role_count': int('$FINAL_COUNT'),
    'ground_truth': {
        'parking_id': '$PARKING_ID',
        'entrance_id': '$ENTRANCE_ID'
    },
    'target_role': json.loads('''$TARGET_ROLE'''),
    'all_roles_raw': json.loads('''$ROLES_JSON''')
}
print(json.dumps(result, indent=2))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"