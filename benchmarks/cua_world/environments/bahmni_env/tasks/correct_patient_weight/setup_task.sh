#!/bin/bash
set -e

echo "=== Setting up correct_patient_weight task ==="

# Source shared Bahmni task utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenMRS to be ready before attempting data seeding
wait_for_bahmni 600

echo "Seeding patient data..."

# create_data.py: Creates patient, visit, and erroneous observation
cat <<EOF > /tmp/create_data.py
import requests
import json
import datetime
import sys
import time

# Disable warnings for self-signed certs
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

BASE_URL = "https://localhost/openmrs"
AUTH = ("superman", "Admin123")
HEADERS = {"Content-Type": "application/json"}
VERIFY_SSL = False

def get_json(url):
    resp = requests.get(f"{BASE_URL}{url}", auth=AUTH, verify=VERIFY_SSL)
    resp.raise_for_status()
    return resp.json()

def post_json(url, payload):
    resp = requests.post(f"{BASE_URL}{url}", json=payload, auth=AUTH, verify=VERIFY_SSL, headers=HEADERS)
    resp.raise_for_status()
    return resp.json()

def setup():
    print("  Getting location...")
    # Get 'Registration Desk' or similar
    loc_resp = get_json("/ws/rest/v1/location?v=default&limit=10")
    location_uuid = loc_resp['results'][0]['uuid']
    for loc in loc_resp['results']:
        if "Registration" in loc['display']:
            location_uuid = loc['uuid']
            break

    print("  Getting identifier type...")
    # Prefer non-validating identifier type
    id_resp = get_json("/ws/rest/v1/patientidentifiertype?v=default")
    id_type_uuid = id_resp['results'][0]['uuid']
    for idt in id_resp['results']:
        if "Patient Identifier" in idt['display']:
            id_type_uuid = idt['uuid']
            break

    # Generate unique identifier
    ts = int(time.time())
    identifier = f"ERR{ts}"

    print(f"  Creating patient Kevin Peterson ({identifier})...")
    patient_payload = {
        "person": {
            "names": [{
                "givenName": "Kevin",
                "familyName": "Peterson",
                "preferred": True
            }],
            "gender": "M",
            "birthdate": "1980-01-01",
            "birthdateEstimated": False
        },
        "identifiers": [{
            "identifier": identifier,
            "identifierType": id_type_uuid,
            "location": location_uuid,
            "preferred": True
        }]
    }
    
    patient = post_json("/ws/rest/v1/patient", patient_payload)
    patient_uuid = patient['uuid']
    
    # Save patient UUID for export script
    with open("/tmp/target_patient_uuid.txt", "w") as f:
        f.write(patient_uuid)

    print("  Creating visit...")
    visit_types = get_json("/ws/rest/v1/visittype")
    visit_type_uuid = visit_types['results'][0]['uuid']
    
    now_str = datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S.000+0000")
    
    visit_payload = {
        "patient": patient_uuid,
        "visitType": visit_type_uuid,
        "location": location_uuid,
        "startDatetime": now_str,
        "stopDatetime": now_str 
    }
    visit = post_json("/ws/rest/v1/visit", visit_payload)
    visit_uuid = visit['uuid']

    print("  Creating encounter with erroneous weight (850kg)...")
    enc_types = get_json("/ws/rest/v1/encountertype")
    # Use 'OPD Consultation' or 'Vitals' or fallback
    enc_type_uuid = enc_types['results'][0]['uuid']
    for et in enc_types['results']:
        if "Consultation" in et['display']:
            enc_type_uuid = et['uuid']
            break

    # Weight concept UUID (CIEL standard)
    weight_concept = "5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    
    enc_payload = {
        "patient": patient_uuid,
        "visit": visit_uuid,
        "encounterType": enc_type_uuid,
        "encounterDatetime": now_str,
        "obs": [
            {
                "concept": weight_concept,
                "value": 850,
                "status": "FINAL"
            }
        ]
    }
    post_json("/ws/rest/v1/encounter", enc_payload)
    print("  Setup data creation complete.")

if __name__ == "__main__":
    try:
        setup()
    except Exception as e:
        print(f"ERROR in python setup: {e}")
        sys.exit(1)
EOF

# Run the data seeding
python3 /tmp/create_data.py

# Launch browser using shared utility (handles SSL warnings etc)
start_browser "$BAHMNI_LOGIN_URL" 4

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="