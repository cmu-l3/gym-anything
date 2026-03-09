#!/bin/bash
set -e

echo "=== Setting up discontinue_medication task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure Bahmni is ready
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni not reachable"
    exit 1
fi

# We use a Python script to set up the specific clinical state (Active Drug Order)
# This is more robust than curl/jq for complex OpenMRS object creation
cat > /tmp/setup_clinical_state.py << 'EOF'
import requests
import json
import sys
import datetime
from requests.auth import HTTPBasicAuth

BASE_URL = "https://localhost/openmrs/ws/rest/v1"
AUTH = HTTPBasicAuth("superman", "Admin123")
HEADERS = {"Content-Type": "application/json"}
VERIFY_SSL = False

def get_json(url):
    try:
        r = requests.get(f"{BASE_URL}{url}", auth=AUTH, verify=VERIFY_SSL)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        print(f"Error getting {url}: {e}")
        return None

def post_json(url, data):
    try:
        r = requests.post(f"{BASE_URL}{url}", auth=AUTH, json=data, verify=VERIFY_SSL)
        if r.status_code not in [200, 201]:
            print(f"Post failed {r.status_code}: {r.text}")
        r.raise_for_status()
        return r.json()
    except Exception as e:
        print(f"Error posting to {url}: {e}")
        return None

# 1. Find Patient
patient_id = "BAH000003"
print(f"Looking up patient {patient_id}...")
results = get_json(f"/patient?q={patient_id}&v=full")
if not results or not results.get("results"):
    print("Patient not found")
    sys.exit(1)
patient_uuid = results["results"][0]["uuid"]
print(f"Found patient: {patient_uuid}")

# 2. Check/Create Visit (Required for placing orders)
# Check for active visit
visits = get_json(f"/visit?patient={patient_uuid}&includeInactive=false")
if not visits or not visits.get("results"):
    print("No active visit, creating one...")
    # Get required metadata
    locs = get_json("/location?tag=Admission+Location&v=default")
    if not locs['results']: locs = get_json("/location?v=default")
    location_uuid = locs["results"][0]["uuid"]
    
    types = get_json("/visittype")
    visit_type_uuid = types["results"][0]["uuid"]
    
    visit_payload = {
        "patient": patient_uuid,
        "visitType": visit_type_uuid,
        "location": location_uuid,
        "startDatetime": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S.000+0000")
    }
    visit = post_json("/visit", visit_payload)
    print("Visit created")
else:
    print("Active visit exists")

# 3. Find Concepts/Metadata for Drug Order
# We need: CareSetting, Concept(Paracetamol), Route(Oral), DoseUnits(mg), Freq(BID)
# This uses standard CIEL/Bahmni metadata if available, or searches.

# CareSetting (Outpatient)
care_settings = get_json("/caresetting")
outpatient_uuid = next((c['uuid'] for c in care_settings['results'] if 'outpatient' in c['display'].lower()), care_settings['results'][0]['uuid'])

# Drug Concept (Paracetamol)
drug_search = get_json("/concept?q=Paracetamol&v=default")
if not drug_search or not drug_search.get("results"):
    print("Paracetamol concept not found")
    sys.exit(1)
concept_uuid = drug_search["results"][0]["uuid"]

# Helper to find concept uuid by name
def find_concept(name):
    res = get_json(f"/concept?q={name}&v=default")
    if res and res.get('results'): return res['results'][0]['uuid']
    return None

route_uuid = find_concept("Oral")
dose_units_uuid = find_concept("mg")
frequency_uuid = get_json("/orderfrequency?v=default")['results'][0]['uuid'] # Just pick first available (e.g. BID)

# 4. Check if order already exists
orders = get_json(f"/order?patient={patient_uuid}&careSetting={outpatient_uuid}&status=active&v=default")
paracetamol_orders = [o for o in orders.get("results", []) if "Paracetamol" in o.get("display", "")]

if paracetamol_orders:
    print("Active Paracetamol order already exists.")
else:
    print("Creating Paracetamol order...")
    # 5. Create Order
    # OpenMRS 1.10+ / 2.x order payload
    order_payload = {
        "type": "drugorder",
        "patient": patient_uuid,
        "concept": concept_uuid,
        "careSetting": outpatient_uuid,
        "orderer": "superman", # ordering provider (needs provider uuid, but 2.x often accepts user uuid or logic handles it. If fails, we need provider lookup)
        # Simplified dosing for robustness
        "dosingType": "org.openmrs.FreeTextDosingInstructions",
        "dosingInstructions": "500mg Oral Twice a day",
        "route": route_uuid,
        # fallback required fields if simple dosing validation is strict
        "dose": 500,
        "doseUnits": dose_units_uuid,
        "frequency": frequency_uuid,
        "numRefills": 0,
        "action": "NEW"
    }
    
    # Provider lookup
    providers = get_json("/provider?q=superman")
    if providers and providers.get("results"):
        order_payload["orderer"] = providers["results"][0]["uuid"]
        
    res = post_json("/order", order_payload)
    if res:
        print(f"Order created: {res['uuid']}")
    else:
        sys.exit(1)

EOF

# Execute the setup python script
echo "Executing clinical state setup..."
python3 /tmp/setup_clinical_state.py

# Start Browser
echo "Starting browser..."
if ! restart_firefox "$BAHMNI_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

focus_firefox || true
sleep 2

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="