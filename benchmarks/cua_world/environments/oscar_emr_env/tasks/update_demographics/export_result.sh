#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load initial state to get the demographic ID
DEMO_NO=$(python3 -c "import json; print(json.load(open('/tmp/initial_demographics.json'))['demographic_no'])" 2>/dev/null || echo "")

if [ -z "$DEMO_NO" ]; then
    echo "ERROR: Could not find demographic ID from initial state."
    exit 1
fi

echo "Querying final state for demographic_no: $DEMO_NO"

# Helper to query DB via python for JSON safety
python3 -c "
import json
import subprocess
import sys

def get_field(field):
    cmd = [
        'docker', 'exec', 'oscar-db', 'mysql', '-u', 'oscar', '-poscar', 'oscar', '-N', '-e',
        f\"SELECT {field} FROM demographic WHERE demographic_no='$DEMO_NO'\"
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout.strip()

# Read initial state
try:
    with open('/tmp/initial_demographics.json', 'r') as f:
        initial = json.load(f)
except FileNotFoundError:
    initial = {}

# Get current state
current = {
    'demographic_no': '$DEMO_NO',
    'address': get_field('address'),
    'city': get_field('city'),
    'province': get_field('province'),
    'postal': get_field('postal'),
    'phone': get_field('phone'),
    'email': get_field('email')
}

# Detect changes (Anti-Gaming)
changed = False
for key in ['address', 'city', 'province', 'postal', 'phone', 'email']:
    if initial.get(key) != current.get(key):
        changed = True
        break

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_state': initial,
    'final_state': current,
    'changes_detected': changed,
    'screenshot_path': '/tmp/task_final.png'
}

# Write to temp file first
with open('/tmp/result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Move to final location
mv /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="