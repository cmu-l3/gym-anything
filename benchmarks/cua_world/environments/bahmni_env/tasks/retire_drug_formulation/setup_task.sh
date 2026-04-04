#!/bin/bash
set -e
echo "=== Setting up retire_drug_formulation task ==="

source /workspace/scripts/task_utils.sh

# Directory for task artifacts
TASK_DIR="/workspace/tasks/retire_drug_formulation"
mkdir -p "$TASK_DIR"

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for Bahmni to be ready
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni did not become ready in time."
    exit 1
fi

# ------------------------------------------------------------------
# Python script to seed the specific Drug Data
# ------------------------------------------------------------------
cat << 'EOF' > /tmp/seed_drug.py
import requests
import json
import sys
import time

BASE_URL = "https://localhost/openmrs/ws/rest/v1"
AUTH = ("superman", "Admin123")
HEADERS = {"Content-Type": "application/json"}
VERIFY = False # Self-signed cert

def get_or_create_concept(name):
    # Try to find existing
    resp = requests.get(f"{BASE_URL}/concept?q={name}&v=default", auth=AUTH, verify=VERIFY)
    if resp.status_code == 200:
        results = resp.json().get("results", [])
        for r in results:
            if r["display"].lower() == name.lower():
                print(f"Found existing concept: {r['uuid']}")
                return r["uuid"]
    
    # If not found, we need to create it. 
    # We need valid Class and Datatype UUIDs. 
    # Fetching "Drug" class and "N/A" datatype usually standard in OpenMRS/CIEL.
    
    # 1. Get Drug Class
    resp = requests.get(f"{BASE_URL}/conceptclass?q=Drug&v=default", auth=AUTH, verify=VERIFY)
    class_uuid = resp.json().get("results", [{}])[0].get("uuid")
    
    # 2. Get N/A Datatype
    resp = requests.get(f"{BASE_URL}/conceptdatatype?q=N/A&v=default", auth=AUTH, verify=VERIFY)
    datatype_uuid = resp.json().get("results", [{}])[0].get("uuid")
    
    if not class_uuid or not datatype_uuid:
        print("Could not find Drug class or N/A datatype to create concept.")
        return None

    payload = {
        "names": [{"name": name, "locale": "en", "conceptNameType": "FULLY_SPECIFIED"}],
        "datatype": datatype_uuid,
        "conceptClass": class_uuid
    }
    
    resp = requests.post(f"{BASE_URL}/concept", auth=AUTH, json=payload, verify=VERIFY)
    if resp.status_code == 201:
        uuid = resp.json()["uuid"]
        print(f"Created concept: {uuid}")
        return uuid
    else:
        print(f"Failed to create concept: {resp.text}")
        return None

def create_or_reset_drug(name, concept_uuid):
    # Check if drug exists
    resp = requests.get(f"{BASE_URL}/drug?q={name}&v=full", auth=AUTH, verify=VERIFY)
    drug_uuid = None
    is_retired = False
    
    if resp.status_code == 200:
        results = resp.json().get("results", [])
        for r in results:
            if r["display"] == name:
                drug_uuid = r["uuid"]
                is_retired = r["retired"]
                break
    
    if drug_uuid:
        print(f"Found existing drug: {drug_uuid}")
        # If retired, un-retire it
        if is_retired:
            print("Drug is retired. Un-retiring...")
            requests.post(f"{BASE_URL}/drug/{drug_uuid}", auth=AUTH, json={"retired": False}, verify=VERIFY)
    else:
        print("Creating new drug...")
        payload = {
            "name": name,
            "concept": concept_uuid,
            "dosageForm": "5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", # Try to use common UUID or omit
            "strength": "25mg"
        }
        # Simplified payload
        payload = {
            "name": name,
            "concept": concept_uuid,
            "combination": False
        }
        resp = requests.post(f"{BASE_URL}/drug", auth=AUTH, json=payload, verify=VERIFY)
        if resp.status_code == 201:
            drug_uuid = resp.json()["uuid"]
            print(f"Created drug: {drug_uuid}")
        else:
            print(f"Failed to create drug: {resp.text}")
            sys.exit(1)
            
    # Write config for verification
    with open("/tmp/task_config.json", "w") as f:
        json.dump({"drug_uuid": drug_uuid, "drug_name": name}, f)

if __name__ == "__main__":
    import urllib3
    urllib3.disable_warnings()
    
    c_uuid = get_or_create_concept("Rofecoxib")
    if c_uuid:
        create_or_reset_drug("Rofecoxib 25mg", c_uuid)
    else:
        sys.exit(1)
EOF

# Execute the python seeder
python3 /tmp/seed_drug.py

# Launch Browser to Login Page
echo "Launching browser..."
start_browser "$BAHMNI_LOGIN_URL"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="