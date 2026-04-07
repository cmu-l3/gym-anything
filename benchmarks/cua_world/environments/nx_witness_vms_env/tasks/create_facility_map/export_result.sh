#!/bin/bash
echo "=== Exporting create_facility_map results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query API for Layout Data
echo "Querying Nx Witness API..."

# Refresh token to ensure access
TOKEN=$(cat "${NX_TOKEN_FILE}" 2>/dev/null || refresh_nx_token)

# Get all layouts
LAYOUTS_JSON=$(curl -sk "${NX_BASE}/rest/v1/layouts" \
    -H "Authorization: Bearer ${TOKEN}" --max-time 15 2>/dev/null || echo "[]")

# Get all devices (to map names to IDs)
DEVICES_JSON=$(curl -sk "${NX_BASE}/rest/v1/devices" \
    -H "Authorization: Bearer ${TOKEN}" --max-time 15 2>/dev/null || echo "[]")

# 3. Create Result JSON
# We use Python to parse and structure the data for the verifier
python3 -c "
import json
import sys
import time

try:
    layouts = json.loads('''$LAYOUTS_JSON''')
    devices = json.loads('''$DEVICES_JSON''')
except:
    layouts = []
    devices = []

# Map device IDs to names
id_to_name = {d.get('id'): d.get('name') for d in devices}

# Find target layout
target_layout = None
for l in layouts:
    if 'warehouse map' in l.get('name', '').lower():
        target_layout = l
        break

result = {
    'layout_found': bool(target_layout),
    'layout_data': target_layout if target_layout else {},
    'device_map': id_to_name,
    'timestamp': time.time()
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 4. Check if app is running
APP_RUNNING=$(pgrep -f "nxwitness" > /dev/null && echo "true" || echo "false")

# Update JSON with app status
# (Using a temp file approach to append)
jq --arg running "$APP_RUNNING" '.app_running = ($running == "true")' /tmp/task_result.json > /tmp/task_result_final.json 2>/dev/null || \
    mv /tmp/task_result.json /tmp/task_result_final.json # fallback if jq fails

mv /tmp/task_result_final.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"