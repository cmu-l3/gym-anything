#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Fetch the final state of the concept using Python
cat <<EOF > /tmp/fetch_result.py
import requests
import json
import sys
import os

# Disable warnings
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

BASE_URL = "${OPENMRS_BASE_URL}"
AUTH = ("${BAHMNI_ADMIN_USERNAME}", "${BAHMNI_ADMIN_PASSWORD}")

try:
    # Load initial state to get UUIDs
    with open("/tmp/initial_concept_state.json", "r") as f:
        initial = json.load(f)
        
    q_uuid = initial['question_uuid']
    
    # Fetch current state
    resp = requests.get(f"{BASE_URL}/ws/rest/v1/concept/{q_uuid}?v=full", auth=AUTH, verify=False)
    if resp.status_code != 200:
        print(f"Failed to fetch concept: {resp.status_code}")
        sys.exit(1)
        
    data = resp.json()
    
    # Extract answers
    answers = []
    for a in data.get('answers', []):
        answers.append({
            "uuid": a['uuid'],
            "display": a['display']
        })
        
    result = {
        "initial_state": initial,
        "final_answers": answers,
        "date_changed": data.get("dateChanged"),
        "task_start": int(os.environ.get("TASK_START", 0)),
        "task_end": int(os.environ.get("TASK_END", 0))
    }
    
    with open("/tmp/task_result.json", "w") as f:
        json.dump(result, f)
        
except Exception as e:
    print(f"Export error: {e}")
    # Create empty failure result
    with open("/tmp/task_result.json", "w") as f:
        json.dump({"error": str(e)}, f)

EOF

export TASK_START
export TASK_END
python3 /tmp/fetch_result.py

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="