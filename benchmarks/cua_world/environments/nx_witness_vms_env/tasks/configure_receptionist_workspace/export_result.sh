#!/bin/bash
set -e
echo "=== Exporting configure_receptionist_workspace results ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_time.txt

# Refresh Token
refresh_nx_token > /dev/null 2>&1 || true

# ==============================================================================
# EXPORT API STATE
# ==============================================================================
echo "Exporting system state..."

# 1. Users
nx_api_get "/rest/v1/users" > /tmp/users_export.json

# 2. User Roles
nx_api_get "/rest/v1/userRoles" > /tmp/roles_export.json

# 3. Layouts
nx_api_get "/rest/v1/layouts" > /tmp/layouts_export.json

# 4. Event Rules (for Soft Triggers)
nx_api_get "/rest/v1/eventRules" > /tmp/rules_export.json

# 5. Devices (Cameras) - needed to map Names to IDs for verification
nx_api_get "/rest/v1/devices" > /tmp/devices_export.json

# ==============================================================================
# SCREENSHOTS
# ==============================================================================
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# Create a consolidated result JSON
python3 -c "
import json, os, glob

def load_json(path):
    try:
        with open(path) as f: return json.load(f)
    except: return []

result = {
    'users': load_json('/tmp/users_export.json'),
    'roles': load_json('/tmp/roles_export.json'),
    'layouts': load_json('/tmp/layouts_export.json'),
    'rules': load_json('/tmp/rules_export.json'),
    'devices': load_json('/tmp/devices_export.json'),
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="