#!/bin/bash
echo "=== Exporting edit_user_role result ==="

source /workspace/scripts/task_utils.sh

# 1. CAPTURE FINAL EVIDENCE
take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. GATHER DATABASE STATE

# Get Target User Final State
# Fields: id, admin_privilege, supervisor_privilege, approved, name
TARGET_DATA=$(opencad_db_query "SELECT id, admin_privilege, supervisor_privilege, approved, name FROM users WHERE email='dispatch@opencad.local'")

# Parse Target Data
# Note: mysql output is tab separated
if [ -n "$TARGET_DATA" ]; then
    T_ID=$(echo "$TARGET_DATA" | awk '{print $1}')
    T_ADMIN=$(echo "$TARGET_DATA" | awk '{print $2}')
    T_SUPER=$(echo "$TARGET_DATA" | awk '{print $3}')
    T_APPROVED=$(echo "$TARGET_DATA" | awk '{print $4}')
    T_NAME=$(echo "$TARGET_DATA" | cut -f5-)
else
    T_ID=""
    T_ADMIN=""
    T_SUPER=""
    T_APPROVED=""
    T_NAME=""
fi

# Get Initial States for Comparison
INITIAL_OTHERS=$(cat /tmp/other_users_initial_state.txt 2>/dev/null)
TARGET_INITIAL_RAW=$(cat /tmp/target_initial_state.txt 2>/dev/null)
T_ADMIN_INITIAL=$(echo "$TARGET_INITIAL_RAW" | awk '{print $2}')
T_APPROVED_INITIAL=$(echo "$TARGET_INITIAL_RAW" | awk '{print $4}')

# Check for Side Effects (did other users change?)
CURRENT_OTHERS=$(opencad_db_query "SELECT GROUP_CONCAT(CONCAT(id, ':', supervisor_privilege) ORDER BY id) FROM users WHERE email != 'dispatch@opencad.local'")

OTHERS_CHANGED="false"
if [ "$INITIAL_OTHERS" != "$CURRENT_OTHERS" ]; then
    OTHERS_CHANGED="true"
fi

# Check if application is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 3. EXPORT JSON
# Use python for safe JSON generation to handle potential weird characters in names
python3 -c "
import json
import os

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'target_user': {
        'exists': bool('$T_ID'),
        'id': '$T_ID',
        'name': '$T_NAME',
        'supervisor_privilege': '$T_SUPER',
        'admin_privilege': '$T_ADMIN',
        'approved': '$T_APPROVED',
        'initial_admin': '$T_ADMIN_INITIAL',
        'initial_approved': '$T_APPROVED_INITIAL'
    },
    'side_effects': {
        'others_modified': $OTHERS_CHANGED,
        'initial_hash': '$INITIAL_OTHERS',
        'final_hash': '$CURRENT_OTHERS'
    },
    'app_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=4)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="