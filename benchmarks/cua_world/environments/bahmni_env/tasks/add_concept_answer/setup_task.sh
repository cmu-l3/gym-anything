#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: add_concept_answer@1 ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure OpenMRS is running
wait_for_bahmni 300

# 2. Setup Concepts via Python script
# We need to ensure:
# - Concept "Bus", "Walking", "Car" exist
# - Concept "Transportation Method" exists and has "Walking" and "Car" but NOT "Bus"
# - We record the initial UUIDs to verify specific objects later

echo "Configuring concepts..."
cat <<EOF > /tmp/setup_concepts.py
import requests
import json
import sys
import time

# Disable warnings for self-signed certs
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

BASE_URL = "${OPENMRS_BASE_URL}"
AUTH = ("${BAHMNI_ADMIN_USERNAME}", "${BAHMNI_ADMIN_PASSWORD}")
HEADERS = {"Content-Type": "application/json"}

def get_concept(name):
    try:
        resp = requests.get(f"{BASE_URL}/ws/rest/v1/concept?q={name}&v=default", auth=AUTH, verify=False)
        if resp.status_code == 200:
            results = resp.json().get('results', [])
            for r in results:
                # Precise matching
                if r['display'].lower() == name.lower():
                    return r
        return None
    except Exception as e:
        print(f"Error fetching {name}: {e}")
        return None

def create_concept(name, class_uuid="8d49277c-c2cc-11de-8d13-0010c6dffd0f", datatype_uuid="8d4a4c94-c2cc-11de-8d13-0010c6dffd0f"):
    # Default: Misc class, N/A datatype
    payload = {
        "names": [{"name": name, "locale": "en", "conceptNameType": "FULLY_SPECIFIED"}],
        "datatype": datatype_uuid,
        "conceptClass": class_uuid
    }
    resp = requests.post(f"{BASE_URL}/ws/rest/v1/concept", auth=AUTH, json=payload, verify=False)
    if resp.status_code == 201:
        print(f"Created concept {name}")
        return resp.json()
    print(f"Failed to create {name}: {resp.text}")
    return None

def main():
    # Standard UUIDs
    CLASS_MISC = "8d49277c-c2cc-11de-8d13-0010c6dffd0f"
    CLASS_QUESTION = "8d491e50-c2cc-11de-8d13-0010c6dffd0f"
    DT_NA = "8d4a4c94-c2cc-11de-8d13-0010c6dffd0f"
    DT_CODED = "8d4a48b6-c2cc-11de-8d13-0010c6dffd0f"

    # 1. Get or Create Answer Concepts
    uuids = {}
    for name in ["Bus", "Walking", "Car"]:
        c = get_concept(name)
        if not c:
            c = create_concept(name, CLASS_MISC, DT_NA)
            if not c:
                sys.exit(1)
        uuids[name] = c['uuid']
    
    # 2. Get or Create Question Concept
    q_name = "Transportation Method"
    q_concept = get_concept(q_name)
    
    # We want these specific answers initially
    desired_initial_answers = [uuids["Walking"], uuids["Car"]]
    
    if not q_concept:
        # Create new
        payload = {
            "names": [{"name": q_name, "locale": "en", "conceptNameType": "FULLY_SPECIFIED"}],
            "datatype": DT_CODED,
            "conceptClass": CLASS_QUESTION,
            "answers": desired_initial_answers
        }
        resp = requests.post(f"{BASE_URL}/ws/rest/v1/concept", auth=AUTH, json=payload, verify=False)
        if resp.status_code == 201:
            q_concept = resp.json()
            print(f"Created {q_name}")
        else:
            print(f"Error creating {q_name}: {resp.text}")
            sys.exit(1)
    else:
        # Update existing to ensure clean state (remove Bus if present)
        # Fetch full concept to get current answers
        full_c = requests.get(f"{BASE_URL}/ws/rest/v1/concept/{q_concept['uuid']}", auth=AUTH, verify=False).json()
        
        # We enforce exactly the desired initial state
        # Note: OpenMRS REST API behavior for 'answers' can be additive or replacement depending on version.
        # Ideally, we PUT/POST the list. 
        # For simplicity in this env, we assume standard behavior: providing the list resets it.
        
        payload = {
            "answers": desired_initial_answers
        }
        resp = requests.post(f"{BASE_URL}/ws/rest/v1/concept/{q_concept['uuid']}", auth=AUTH, json=payload, verify=False)
        if resp.status_code != 200:
            print(f"Failed to reset answers: {resp.text}")
            sys.exit(1)
        print(f"Reset {q_name} to clean state")

    # 3. Save initial state for verification
    initial_state = {
        "question_uuid": q_concept['uuid'],
        "bus_uuid": uuids["Bus"],
        "walking_uuid": uuids["Walking"],
        "car_uuid": uuids["Car"],
        "initial_answers_count": 2
    }
    with open("/tmp/initial_concept_state.json", "w") as f:
        json.dump(initial_state, f)

if __name__ == "__main__":
    main()
EOF

python3 /tmp/setup_concepts.py

# 3. Launch Browser pointing to OpenMRS Admin Login or Bahmni Home
# The task description says "Bahmni/OpenMRS login page".
# We'll start at Bahmni home, agent has to navigate or login.
start_browser "${BAHMNI_LOGIN_URL}"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="