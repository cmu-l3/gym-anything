#!/bin/bash
echo "=== Exporting discontinue_medication result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data via Python
# We query OpenMRS API to get the current state of orders for the patient
# This allows the verifier to check the database state without needing direct DB access

cat > /tmp/fetch_results.py << 'EOF'
import requests
import json
import sys
from requests.auth import HTTPBasicAuth

BASE_URL = "https://localhost/openmrs/ws/rest/v1"
AUTH = HTTPBasicAuth("superman", "Admin123")
VERIFY_SSL = False
PATIENT_ID = "BAH000003"
TASK_START_FILE = "/tmp/task_start_time.txt"

def get_json(url):
    try:
        r = requests.get(f"{BASE_URL}{url}", auth=AUTH, verify=VERIFY_SSL)
        return r.json() if r.status_code == 200 else {}
    except:
        return {}

result = {
    "patient_found": False,
    "orders": [],
    "task_start_time": 0
}

# Get task start time
try:
    with open(TASK_START_FILE, 'r') as f:
        result["task_start_time"] = int(f.read().strip())
except:
    pass

# Find Patient
pat_res = get_json(f"/patient?q={PATIENT_ID}&v=default")
if pat_res.get("results"):
    patient_uuid = pat_res["results"][0]["uuid"]
    result["patient_found"] = True
    
    # Get ALL orders (active and inactive) to find the discontinued one
    # Note: status=any is important to find stopped orders
    orders_res = get_json(f"/order?patient={patient_uuid}&v=full&status=any")
    
    if orders_res.get("results"):
        # Filter slightly to reduce JSON size, but keep relevant fields
        for order in orders_res["results"]:
            # We are interested in Paracetamol drug orders
            if "Paracetamol" in order.get("drug", {}).get("display", "") or \
               "Paracetamol" in order.get("concept", {}).get("display", ""):
                
                simplified_order = {
                    "uuid": order.get("uuid"),
                    "action": order.get("action"),
                    "dateActivated": order.get("dateActivated"),
                    "dateStopped": order.get("dateStopped"),
                    "orderReason": order.get("orderReason"), # UUID or concept object
                    "orderReasonNonCoded": order.get("orderReasonNonCoded"),
                    "display": order.get("display")
                }
                
                # Fetch full concept name for orderReason if it's a coded concept
                if isinstance(simplified_order["orderReason"], dict):
                     simplified_order["reason_display"] = simplified_order["orderReason"].get("display")
                
                result["orders"].append(simplified_order)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Data exported successfully")
EOF

python3 /tmp/fetch_results.py

# Set permissions so the host can read it (via copy_from_env)
chmod 644 /tmp/task_result.json 2>/dev/null || true
chmod 644 /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="