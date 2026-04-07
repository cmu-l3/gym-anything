#!/bin/bash
echo "=== Exporting create_incident_bookmarks result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get verification data
TOKEN=$(get_nx_token)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INCIDENT_START=$(cat /home/ga/incident_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_bookmark_count.txt 2>/dev/null || echo "0")

# 3. Fetch current bookmarks
echo "Fetching bookmarks..."
BOOKMARKS_JSON=$(curl -sk "${NX_BASE}/rest/v1/bookmarks" -H "Authorization: Bearer ${TOKEN}" 2>/dev/null || echo "[]")
FINAL_COUNT=$(echo "$BOOKMARKS_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

# 4. Fetch device list to map Names -> IDs
echo "Fetching devices..."
DEVICES_JSON=$(curl -sk "${NX_BASE}/rest/v1/devices" -H "Authorization: Bearer ${TOKEN}" 2>/dev/null || echo "[]")

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys, time

try:
    bookmarks = json.loads('''$BOOKMARKS_JSON''')
    devices = json.loads('''$DEVICES_JSON''')
except:
    bookmarks = []
    devices = []

# Create a map of device_id -> device_name and name -> id
device_map = {}
for d in devices:
    d_id = d.get('id')
    d_name = d.get('name')
    if d_id and d_name:
        device_map[d_id] = d_name

result = {
    'task_start_time': int('$TASK_START'),
    'incident_start_time': int('$INCIDENT_START'),
    'initial_bookmark_count': int('$INITIAL_COUNT'),
    'final_bookmark_count': len(bookmarks),
    'bookmarks': bookmarks,
    'device_map': device_map,
    'screenshot_path': '/tmp/task_final.png'
}

print(json.dumps(result, indent=2))
" > "$TEMP_JSON"

# 6. Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="