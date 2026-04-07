#!/bin/bash
# Export: assign_user_role task
# Fetches the final state of the user via REST API to verify roles.

echo "=== Exporting assign_user_role results ==="
source /workspace/scripts/task_utils.sh

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TARGET_USER_UUID=$(cat /tmp/target_user_uuid.txt 2>/dev/null || echo "")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Fetch final user state
echo "Fetching final user state..."
if [ -n "$TARGET_USER_UUID" ]; then
    USER_DATA=$(omrs_get "/user/$TARGET_USER_UUID?v=full")
else
    # Fallback search if UUID file lost
    echo "Warning: UUID file missing, searching by username..."
    SEARCH=$(omrs_get "/user?q=nurse_betty&v=full")
    USER_DATA=$(echo "$SEARCH" | python3 -c "import sys,json; r=json.load(sys.stdin).get('results',[]); print(json.dumps(r[0]) if r else '{}')")
fi

# Save raw data for verifier
echo "$USER_DATA" > /tmp/user_final_state.json

# Construct result JSON
# We do some pre-processing in python to make the JSON clean
python3 -c "
import json
import os
import time

try:
    with open('/tmp/user_final_state.json', 'r') as f:
        user_data = json.load(f)
except Exception:
    user_data = {}

roles = [r.get('display', '') for r in user_data.get('roles', [])]
target_role = 'Organizational Doctor'
has_role = target_role in roles
retired = user_data.get('retired', False)
username = user_data.get('username', '')

result = {
    'task_start': int('$TASK_START'),
    'task_end': int('$TASK_END'),
    'user_found': bool(username),
    'username': username,
    'roles_found': roles,
    'has_target_role': has_role,
    'is_retired': retired,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="