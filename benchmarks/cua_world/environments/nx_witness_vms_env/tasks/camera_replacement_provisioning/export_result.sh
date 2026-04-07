#!/bin/bash
set -e
echo "=== Exporting Camera Replacement Results ==="

source /workspace/scripts/task_utils.sh

# Paths
GROUND_TRUTH_FILE="/var/lib/app/ground_truth/camera_ids.json"
REPORT_PATH="/home/ga/maintenance_report.json"
RESULT_JSON="/tmp/task_result.json"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Read Ground Truth IDs (to know which devices to check)
if [ ! -f "$GROUND_TRUTH_FILE" ]; then
    echo "ERROR: Ground truth file missing"
    exit 1
fi

FAULTY_ID=$(python3 -c "import sys,json; print(json.load(open('$GROUND_TRUTH_FILE')).get('faulty_id',''))")
NEW_ID=$(python3 -c "import sys,json; print(json.load(open('$GROUND_TRUTH_FILE')).get('new_id',''))")

# 4. Query Final State of Devices via API
# We do this inside the container and export the JSON to avoid networking issues for the host verifier
echo "Querying device states..."
refresh_nx_token > /dev/null 2>&1 || true

FAULTY_STATE=$(nx_api_get "/rest/v1/devices/${FAULTY_ID}")
NEW_STATE=$(nx_api_get "/rest/v1/devices/${NEW_ID}")

# 5. Check Report File
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_CONTENT="{}"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Check if valid JSON
    if cat "$REPORT_PATH" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        REPORT_VALID="true"
        REPORT_CONTENT=$(cat "$REPORT_PATH")
    fi
fi

# 6. Construct Result JSON
# We embed the raw API responses so the verifier can parse them logic-side
python3 -c "
import json
import os

try:
    faulty_state = json.loads('''$FAULTY_STATE''')
except:
    faulty_state = {}

try:
    new_state = json.loads('''$NEW_STATE''')
except:
    new_state = {}

try:
    report_content = json.loads('''$REPORT_CONTENT''')
except:
    report_content = {}

result = {
    'timestamp': '$TASK_END',
    'faulty_camera_state': faulty_state,
    'new_camera_state': new_state,
    'report_exists': $REPORT_EXISTS,
    'report_valid': $REPORT_VALID,
    'report_content': report_content,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so copy_from_env can read it
chmod 644 "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON" | head -n 20