#!/bin/bash
echo "=== Exporting Retire Provider Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# 2. Check if Application (Epiphany) is running
APP_RUNNING="false"
if pgrep -f epiphany > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Query OpenMRS API for the target provider status
# We use python to query and format the JSON result to ensure correctness
cat <<EOF > /tmp/check_provider_status.py
import requests
import json
import sys
import warnings
import os

warnings.filterwarnings("ignore")

BASE_URL = "${OPENMRS_API_URL}"
AUTH = ("${BAHMNI_ADMIN_USERNAME}", "${BAHMNI_ADMIN_PASSWORD}")

def check_status():
    result = {
        "provider_found": False,
        "is_retired": False,
        "retire_reason": None,
        "uuid": None,
        "audit_modified_date": None
    }

    # Query for the specific provider including voided/retired records
    try:
        resp = requests.get(f"{BASE_URL}/provider?q=PROV-TEMP&v=full&includeAll=true", auth=AUTH, verify=False)
        data = resp.json()
        
        results = data.get("results", [])
        target_provider = None
        
        # Find exact match for identifier
        for p in results:
            if p.get("identifier") == "PROV-TEMP":
                target_provider = p
                break
        
        if target_provider:
            result["provider_found"] = True
            result["uuid"] = target_provider.get("uuid")
            result["is_retired"] = target_provider.get("retired", False)
            result["retire_reason"] = target_provider.get("retireReason")
            
            # Get audit info if available
            audit = target_provider.get("auditInfo", {})
            result["audit_date_retired"] = audit.get("dateRetired")
            result["audit_date_changed"] = audit.get("dateChanged")

        # Sanity check: Ensure we didn't retire the Super User (admin)
        # Provider ID 1 is usually Super User. Query by uuid if known or just check first result.
        # We'll just do a quick check on 'superman' provider if it exists.
        resp_admin = requests.get(f"{BASE_URL}/provider?q=superman&v=default", auth=AUTH, verify=False)
        admin_results = resp_admin.json().get("results", [])
        if admin_results:
             result["admin_provider_retired"] = admin_results[0].get("retired", False)
        else:
             result["admin_provider_retired"] = False

    except Exception as e:
        result["error"] = str(e)

    return result

if __name__ == "__main__":
    status = check_status()
    with open("/tmp/api_result.json", "w") as f:
        json.dump(status, f)
EOF

python3 /tmp/check_provider_status.py

# 4. Compile final result JSON
# Merge API result with environment metadata
python3 -c "
import json
import os
import time

try:
    with open('/tmp/api_result.json', 'r') as f:
        api_data = json.load(f)
except:
    api_data = {}

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = int(f.read().strip())
except:
    start_time = 0

final_result = {
    'task_start': start_time,
    'task_end': int(time.time()),
    'app_was_running': '$APP_RUNNING' == 'true',
    'screenshot_exists': os.path.exists('/tmp/task_final.png'),
    'api_data': api_data
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_result, f, indent=2)
"

# Set permissions so the host can read it (if mounting logic requires it, 
# though copy_from_env handles this usually)
chmod 644 /tmp/task_result.json

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export Complete ==="