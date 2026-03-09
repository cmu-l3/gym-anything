#!/bin/bash
echo "=== Exporting retire_drug_formulation results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONFIG_FILE="/tmp/task_config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found. Setup failed?"
    echo "{}" > /tmp/task_result.json
    exit 1
fi

DRUG_UUID=$(jq -r '.drug_uuid' "$CONFIG_FILE")
echo "Checking status for Drug UUID: $DRUG_UUID"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query OpenMRS API for the final state of the drug
# We use python for robust JSON parsing
cat << EOF > /tmp/check_status.py
import requests
import json
import sys

BASE_URL = "https://localhost/openmrs/ws/rest/v1"
AUTH = ("superman", "Admin123")
DRUG_UUID = "$DRUG_UUID"

import urllib3
urllib3.disable_warnings()

try:
    resp = requests.get(f"{BASE_URL}/drug/{DRUG_UUID}?v=full", auth=AUTH, verify=False)
    if resp.status_code == 200:
        data = resp.json()
        result = {
            "exists": True,
            "uuid": data.get("uuid"),
            "retired": data.get("retired", False),
            "retireReason": data.get("retireReason", ""),
            "auditInfo": data.get("auditInfo", {}) # Contains dateChanged/dateRetired often
        }
    else:
        result = {"exists": False, "error": resp.status_code}
except Exception as e:
    result = {"exists": False, "error": str(e)}

with open("/tmp/api_result.json", "w") as f:
    json.dump(result, f)
EOF

python3 /tmp/check_status.py

# Combine info into final result
# We check if 'dateRetired' is available in the API response logic above, 
# but usually REST API v=full returns 'auditInfo' or direct fields depending on version.
# We will trust the verifier to parse the JSON.

cat << EOF > /tmp/final_combiner.py
import json
import os
import time

try:
    with open("/tmp/api_result.json", "r") as f:
        api_data = json.load(f)
except:
    api_data = {}

task_start = $TASK_START
task_end = $TASK_END

final_output = {
    "task_start": task_start,
    "task_end": task_end,
    "drug_data": api_data,
    "screenshot_path": "/tmp/task_final.png"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(final_output, f)
EOF

python3 /tmp/final_combiner.py

# Set permissions for copy_from_env
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="