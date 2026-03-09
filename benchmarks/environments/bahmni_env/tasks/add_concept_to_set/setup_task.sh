#!/bin/bash
set -e
echo "=== Setting up add_concept_to_set task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Bahmni/OpenMRS to be ready
if ! wait_for_bahmni 600; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# Python script to setup concepts via OpenMRS REST API
cat > /tmp/setup_concepts.py << 'PYEOF'
import requests
import json
import sys
import time

# Configuration
BASE_URL = "https://localhost/openmrs/ws/rest/v1"
AUTH = ("superman", "Admin123")
HEADERS = {"Content-Type": "application/json"}
VERIFY_SSL = False

# Standard UUIDs (CIEL/OpenMRS defaults)
DATATYPE_NA = "8d4a4c94-c2cc-11de-8d13-0010c6dffd0f"
DATATYPE_NUMERIC = "8d4a4488-c2cc-11de-8d13-0010c6dffd0f"
CLASS_CONVSET = "8d492594-c2cc-11de-8d13-0010c6dffd0f"
CLASS_TEST = "8d4907b2-c2cc-11de-8d13-0010c6dffd0f"

def get_concept_by_name(name):
    try:
        resp = requests.get(f"{BASE_URL}/concept", params={"q": name, "v": "full"}, auth=AUTH, verify=VERIFY_SSL)
        results = resp.json().get("results", [])
        for r in results:
            # Exact match on display name or one of the names
            if r["display"].lower() == name.lower() or r["name"]["display"].lower() == name.lower():
                return r
        return None
    except Exception as e:
        print(f"Error fetching {name}: {e}")
        return None

def create_concept(name, class_uuid, datatype_uuid, is_set=False):
    payload = {
        "names": [{"name": name, "locale": "en", "conceptNameType": "FULLY_SPECIFIED"}],
        "datatype": datatype_uuid,
        "conceptClass": class_uuid,
        "set": is_set
    }
    resp = requests.post(f"{BASE_URL}/concept", json=payload, auth=AUTH, headers=HEADERS, verify=VERIFY_SSL)
    if resp.status_code == 201:
        return resp.json()
    print(f"Failed to create {name}: {resp.text}")
    return None

def update_set_members(set_uuid, members):
    # OpenMRS REST API replaces the list, so we provide the list of member UUIDs
    payload = {"setMembers": members}
    resp = requests.post(f"{BASE_URL}/concept/{set_uuid}", json=payload, auth=AUTH, headers=HEADERS, verify=VERIFY_SSL)
    return resp.status_code == 200

# 1. Setup Serum Magnesium (Test)
magnesium = get_concept_by_name("Serum Magnesium")
if not magnesium:
    print("Creating Serum Magnesium...")
    magnesium = create_concept("Serum Magnesium", CLASS_TEST, DATATYPE_NUMERIC, is_set=False)
    if not magnesium:
        sys.exit(1)
magnesium_uuid = magnesium["uuid"]

# 2. Setup Electrolytes Panel (Set)
panel = get_concept_by_name("Electrolytes Panel")
if not panel:
    print("Creating Electrolytes Panel...")
    panel = create_concept("Electrolytes Panel", CLASS_CONVSET, DATATYPE_NA, is_set=True)
    if not panel:
        sys.exit(1)
panel_uuid = panel["uuid"]

# 3. Ensure Magnesium is NOT in Panel initially
current_members = [m["uuid"] for m in panel.get("setMembers", [])]
if magnesium_uuid in current_members:
    print("Removing Magnesium from Panel for initial state...")
    new_members = [m for m in current_members if m != magnesium_uuid]
    update_set_members(panel_uuid, new_members)

# Save UUIDs for verifier
metadata = {
    "panel_uuid": panel_uuid,
    "magnesium_uuid": magnesium_uuid
}
with open("/tmp/concept_metadata.json", "w") as f:
    json.dump(metadata, f)

print("Concepts setup complete.")
PYEOF

# Execute setup script
python3 /tmp/setup_concepts.py

# Launch Browser to OpenMRS Admin
# We use restart_browser from task_utils to handle Epiphany specifics
restart_browser "https://localhost/openmrs/admin" 4

# Focus and maximize
focus_browser
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="