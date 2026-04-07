#!/bin/bash
echo "=== Exporting import_incident_log_csv result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_FILE="/home/ga/Documents/acs_exceptions.csv"

# 1. Dump the CSV file used (to verify timestamps against)
CSV_CONTENT=$(cat "$CSV_FILE" | base64 -w 0)

# 2. Dump all Devices (ID -> Name mapping)
echo "Fetching devices..."
DEVICES_JSON=$(nx_api_get "/rest/v1/devices")

# 3. Dump all Bookmarks for all devices
echo "Fetching bookmarks..."
ALL_BOOKMARKS="[]"

# Python script to aggregate bookmarks from all devices into a single JSON list
# We iterate inside Python to handle the JSON array logic cleaner
python3 -c "
import sys, json, requests, urllib3
urllib3.disable_warnings()

token = '$(get_nx_token)'
base_url = '${NX_BASE}'
headers = {'Authorization': f'Bearer {token}'}

try:
    devices = json.loads('''${DEVICES_JSON}''')
except:
    devices = []

all_bookmarks = []

for dev in devices:
    dev_id = dev.get('id')
    dev_name = dev.get('name')
    if not dev_id: continue
    
    try:
        url = f'{base_url}/rest/v1/devices/{dev_id}/bookmarks'
        res = requests.get(url, headers=headers, verify=False, timeout=5)
        if res.status_code == 200:
            bks = res.json()
            # Enrich bookmark with device info for the verifier
            for b in bks:
                b['_deviceId'] = dev_id
                b['_deviceName'] = dev_name
            all_bookmarks.extend(bks)
    except Exception as e:
        pass

print(json.dumps(all_bookmarks))
" > /tmp/all_bookmarks.json

BOOKMARKS_JSON=$(cat /tmp/all_bookmarks.json)

# 4. Check for Agent's Script (Evidence of work)
SCRIPT_FOUND="false"
# Look for common python script names or recent py files
RECENT_PY=$(find /home/ga -name "*.py" -newermt "@$TASK_START" 2>/dev/null | head -n 1)
if [ -n "$RECENT_PY" ]; then
    SCRIPT_FOUND="true"
fi

# 5. Capture final screenshot
take_screenshot /tmp/task_final.png

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "csv_content_base64": "$CSV_CONTENT",
    "devices": $DEVICES_JSON,
    "bookmarks": $BOOKMARKS_JSON,
    "script_found": $SCRIPT_FOUND,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="