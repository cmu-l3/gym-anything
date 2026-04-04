#!/bin/bash
set -e
echo "=== Setting up Retire Provider task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for OpenMRS to be ready
if ! wait_for_http "${OPENMRS_API_URL}/session" 600; then
  echo "ERROR: OpenMRS is not reachable"
  exit 1
fi

# Create the target provider using Python for cleaner API interaction
echo "Creating target provider (Dr. Temporary Provider)..."
cat <<EOF > /tmp/create_provider.py
import requests
import json
import sys
import warnings

# Suppress self-signed cert warnings
warnings.filterwarnings("ignore")

BASE_URL = "${OPENMRS_API_URL}"
AUTH = ("${BAHMNI_ADMIN_USERNAME}", "${BAHMNI_ADMIN_PASSWORD}")
HEADERS = {"Content-Type": "application/json"}

def get_identifier_type_uuid():
    """Get a valid identifier type UUID."""
    resp = requests.get(f"{BASE_URL}/patientidentifiertype?v=default", auth=AUTH, verify=False)
    results = resp.json().get("results", [])
    if results:
        return results[0]["uuid"]
    return None

def create_provider():
    # 1. Check if provider already exists
    resp = requests.get(f"{BASE_URL}/provider?q=PROV-TEMP&v=full&includeAll=true", auth=AUTH, verify=False)
    results = resp.json().get("results", [])
    
    for prov in results:
        if prov.get("identifier") == "PROV-TEMP":
            uuid = prov["uuid"]
            # If retired, unretire it to ensure clean starting state
            if prov.get("retired"):
                print(f"Unretiring existing provider {uuid}...")
                requests.post(f"{BASE_URL}/provider/{uuid}", 
                              auth=AUTH, json={"retired": False, "retireReason": None}, headers=HEADERS, verify=False)
            else:
                print(f"Provider {uuid} exists and is active.")
            return uuid

    # 2. Create Person for Provider first (OpenMRS 2.x model)
    # Note: In some OpenMRS configs, providers don't strictly need a person, 
    # but in Bahmni/OpenMRS 2.x it's standard.
    person_payload = {
        "names": [{
            "givenName": "Temporary", 
            "familyName": "Provider"
        }],
        "gender": "M",
        "birthdate": "1980-01-01",
        "birthdateEstimated": False
    }
    
    # Create person
    print("Creating person...")
    p_resp = requests.post(f"{BASE_URL}/person", auth=AUTH, json=person_payload, headers=HEADERS, verify=False)
    if p_resp.status_code not in (200, 201):
        # If person creation fails, try creating provider without person link 
        # (some legacy modes support this, though deprecated)
        print(f"Person creation warning: {p_resp.status_code}. Attempting direct provider creation.")
        provider_payload = {
            "identifier": "PROV-TEMP",
            "name": "Dr. Temporary Provider"
        }
    else:
        person_uuid = p_resp.json()["uuid"]
        provider_payload = {
            "identifier": "PROV-TEMP",
            "person": person_uuid
        }

    print("Creating new provider PROV-TEMP...")
    resp = requests.post(f"{BASE_URL}/provider", auth=AUTH, json=provider_payload, headers=HEADERS, verify=False)
    
    if resp.status_code not in (200, 201):
        print(f"ERROR: Failed to create provider: {resp.status_code} {resp.text}")
        sys.exit(1)
        
    return resp.json()["uuid"]

if __name__ == "__main__":
    try:
        uuid = create_provider()
        print(f"SUCCESS: Provider ready: {uuid}")
    except Exception as e:
        print(f"ERROR: {e}")
        sys.exit(1)
EOF

# Execute the python script
python3 /tmp/create_provider.py

# Launch the browser pointing to the OpenMRS Admin page
echo "Launching browser..."
start_browser "https://localhost/openmrs/admin" 4

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="