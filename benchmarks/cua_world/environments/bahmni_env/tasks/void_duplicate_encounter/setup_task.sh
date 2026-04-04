#!/bin/bash
set -e
echo "=== Setting up Void Duplicate Encounter Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# Create the Python injection script
cat > /tmp/inject_dupes.py << 'EOF'
import requests
import json
import sys
import datetime
import warnings
from requests.auth import HTTPBasicAuth

# Suppress insecure request warnings
warnings.filterwarnings("ignore")

BASE_URL = "https://localhost/openmrs"
USERNAME = "superman"
PASSWORD = "Admin123"
PATIENT_IDENTIFIER = "BAH000008" # Lisa Thompson

def main():
    auth = HTTPBasicAuth(USERNAME, PASSWORD)
    headers = {"Content-Type": "application/json"}
    
    # 1. Find Patient
    print(f"Finding patient {PATIENT_IDENTIFIER}...")
    resp = requests.get(f"{BASE_URL}/ws/rest/v1/patient", params={'q': PATIENT_IDENTIFIER, 'v': 'full'}, auth=auth, verify=False)
    resp.raise_for_status()
    results = resp.json().get('results', [])
    if not results:
        print(f"Error: Patient {PATIENT_IDENTIFIER} not found")
        sys.exit(1)
    patient_uuid = results[0]['uuid']
    
    # 2. Find or Create Active Visit
    print("Ensuring active visit...")
    resp = requests.get(f"{BASE_URL}/ws/rest/v1/visit", params={'patient': patient_uuid, 'v': 'default'}, auth=auth, verify=False)
    visits = resp.json().get('results', [])
    
    visit_uuid = None
    # Check for an active visit (no stopDatetime or stopDatetime in future)
    for v in visits:
        if not v.get('stopDatetime'):
            visit_uuid = v['uuid']
            break
            
    if not visit_uuid:
        # Create a visit
        loc_resp = requests.get(f"{BASE_URL}/ws/rest/v1/location?tag=Visit%20Location", auth=auth, verify=False)
        location_uuid = loc_resp.json()['results'][0]['uuid']
        
        vt_resp = requests.get(f"{BASE_URL}/ws/rest/v1/visittype", auth=auth, verify=False)
        visit_type_uuid = vt_resp.json()['results'][0]['uuid']
        
        visit_payload = {
            "patient": patient_uuid,
            "visitType": visit_type_uuid,
            "location": location_uuid,
            "startDatetime": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S.000+0000")
        }
        resp = requests.post(f"{BASE_URL}/ws/rest/v1/visit", json=visit_payload, auth=auth, headers=headers, verify=False)
        visit_uuid = resp.json()['uuid']

    # 3. Find Encounter Type 'Vitals'
    resp = requests.get(f"{BASE_URL}/ws/rest/v1/encountertype", params={'q': 'Vitals'}, auth=auth, verify=False)
    results = resp.json().get('results', [])
    if not results:
        # Fallback to first available if Vitals missing (unlikely in Bahmni)
        resp = requests.get(f"{BASE_URL}/ws/rest/v1/encountertype", auth=auth, verify=False)
        encounter_type_uuid = resp.json()['results'][0]['uuid']
    else:
        encounter_type_uuid = results[0]['uuid']

    # 4. Create Duplicate Encounters
    print("Injecting duplicate encounters...")
    encounter_uuids = []
    
    # Create two identical encounters
    for i in range(2):
        payload = {
            "patient": patient_uuid,
            "visit": visit_uuid,
            "encounterType": encounter_type_uuid,
            "encounterDatetime": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S.000+0000"),
            "obs": [] # Empty obs is fine for this admin task
        }
        
        resp = requests.post(f"{BASE_URL}/ws/rest/v1/encounter", json=payload, auth=auth, headers=headers, verify=False)
        if resp.status_code == 201:
            enc_uuid = resp.json()['uuid']
            encounter_uuids.append(enc_uuid)
            print(f"Created encounter {i+1}: {enc_uuid}")
        else:
            print(f"Failed to create encounter: {resp.text}")

    # Output JSON to stdout for capture
    result = {
        "patient_uuid": patient_uuid,
        "visit_uuid": visit_uuid,
        "encounter_uuids": encounter_uuids
    }
    
    with open("/tmp/dupes_injection.json", "w") as f:
        json.dump(result, f)

if __name__ == "__main__":
    main()
EOF

# Run the injection script
python3 /tmp/inject_dupes.py

# Save the sensitive task data to a hidden location for the export script
# We put it in /root to keep it safe from the 'ga' user if possible, 
# but for verification simplicity we'll put it in a hidden file in /tmp 
# and rely on the agent not explicitly looking for it.
if [ -f "/tmp/dupes_injection.json" ]; then
    cp /tmp/dupes_injection.json /tmp/.task_data_hidden.json
    chmod 644 /tmp/.task_data_hidden.json
    echo "Duplicate data injected successfully."
else
    echo "ERROR: Failed to inject duplicate data."
    exit 1
fi

# Start Epiphany browser at login page
if ! restart_firefox "$BAHMNI_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="