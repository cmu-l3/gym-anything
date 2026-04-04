#!/bin/bash
echo "=== Exporting Void Duplicate Encounter Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create python script to check status
cat > /tmp/check_status.py << 'EOF'
import requests
import json
import sys
import warnings
from requests.auth import HTTPBasicAuth

warnings.filterwarnings("ignore")

BASE_URL = "https://localhost/openmrs"
USERNAME = "superman"
PASSWORD = "Admin123"
DATA_FILE = "/tmp/.task_data_hidden.json"

def main():
    # Load setup data
    try:
        with open(DATA_FILE, 'r') as f:
            setup_data = json.load(f)
    except FileNotFoundError:
        print(json.dumps({"error": "Setup data file not found"}))
        return

    encounter_uuids = setup_data.get("encounter_uuids", [])
    patient_uuid = setup_data.get("patient_uuid", "")
    
    auth = HTTPBasicAuth(USERNAME, PASSWORD)
    
    encounters_status = []
    
    # Check each encounter
    for uuid in encounter_uuids:
        resp = requests.get(f"{BASE_URL}/ws/rest/v1/encounter/{uuid}", auth=auth, verify=False)
        if resp.status_code == 200:
            data = resp.json()
            encounters_status.append({
                "uuid": uuid,
                "voided": data.get("voided", False),
                "voidReason": data.get("voidReason", "")
            })
        else:
            encounters_status.append({"uuid": uuid, "error": resp.status_code})
            
    # Check patient integrity (should NOT be voided)
    patient_voided = False
    if patient_uuid:
        p_resp = requests.get(f"{BASE_URL}/ws/rest/v1/patient/{patient_uuid}", auth=auth, verify=False)
        if p_resp.status_code == 200:
            patient_voided = p_resp.json().get("voided", False)
            
    result = {
        "encounters": encounters_status,
        "patient_voided": patient_voided,
        "screenshot_path": "/tmp/task_final.png"
    }
    
    print(json.dumps(result))

if __name__ == "__main__":
    main()
EOF

# Run checker and save to json
python3 /tmp/check_status.py > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="