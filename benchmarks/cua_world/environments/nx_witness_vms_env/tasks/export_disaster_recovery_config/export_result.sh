#!/bin/bash
set -e
echo "=== Exporting export_disaster_recovery_config result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/dr_export/disaster_recovery_config.json"
GROUND_TRUTH_PATH="/tmp/dr_ground_truth.json"

# 1. Check if output file exists and when it was created
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Generate Ground Truth Data (to verify agent's export against)
# We use the environment's trusted python/curl to fetch the real state now.
echo "Generating ground truth data..."

python3 -c "
import json
import requests
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

base_url = 'https://localhost:7001'
token = '$(get_nx_token)'
headers = {'Authorization': f'Bearer {token}'}

def get_api(endpoint):
    try:
        resp = requests.get(f'{base_url}{endpoint}', headers=headers, verify=False, timeout=10)
        return resp.json()
    except:
        return []

data = {
    'systemInfo': get_api('/rest/v1/system/info'),
    'servers': get_api('/rest/v1/servers'),
    'devices': get_api('/rest/v1/devices'),
    'users': get_api('/rest/v1/users'),
    'layouts': get_api('/rest/v1/layouts'),
    'eventRules': get_api('/rest/v1/rules'),
    'systemSettings': get_api('/rest/v1/system/settings')
}

with open('$GROUND_TRUTH_PATH', 'w') as f:
    json.dump(data, f, indent=2)
" || echo "Failed to generate ground truth"

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare result JSON for verifier
# We don't analyze the JSON content deep here, we leave that to the python verifier.
# We just verify file attributes.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "ground_truth_path": "$GROUND_TRUTH_PATH"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="