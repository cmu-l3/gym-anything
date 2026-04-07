#!/bin/bash
echo "=== Exporting Bulk User Provisioning Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# Gather Verification Data
# ==============================================================================

# Refresh token to ensure we can query
NX_TOKEN=$(refresh_nx_token)

# 1. Get all Users (to verify creation and attributes)
echo "Fetching users..."
ALL_USERS_JSON=$(nx_api_get "/rest/v1/users")

# 2. Get all Roles (to verify name-to-id mapping)
echo "Fetching roles..."
ALL_ROLES_JSON=$(nx_api_get "/rest/v1/userRoles")

# 3. Check for automation scripts (evidence of programmatic approach)
# We look for .py or .sh files created in Documents or Home during the task
echo "Checking for script files..."
SCRIPT_FILES=$(find /home/ga -maxdepth 2 -name "*.py" -o -name "*.sh" -newermt "@$TASK_START" 2>/dev/null | grep -v "task_utils" || echo "")
SCRIPT_CREATED="false"
if [ -n "$SCRIPT_FILES" ]; then
    SCRIPT_CREATED="true"
fi

# Save raw data to JSON for the Python verifier to process
# We use python to construct the JSON safely to avoid string escaping issues
python3 -c "
import json
import os
import sys

try:
    users = json.loads('''$ALL_USERS_JSON''')
except:
    users = []

try:
    roles = json.loads('''$ALL_ROLES_JSON''')
except:
    roles = []

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'script_created': $SCRIPT_CREATED,
    'users': users,
    'roles': roles,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="