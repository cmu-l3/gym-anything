#!/bin/bash
echo "=== Setting up Task: Link Incidents to Problem ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure SDP is running
ensure_sdp_running

# 2. Get API Key for setup (try DB first, then web generation if needed)
echo "Retrieving API key..."
API_KEY=$(get_sdp_api_key_from_db)

if [ -z "$API_KEY" ]; then
    echo "API Key not found in DB. Attempting generation via web..."
    # Ensure helper script exists
    if [ ! -f /tmp/sdp_login.py ]; then
        write_python_login_script
    fi
    API_KEY=$(generate_api_key_via_web)
fi

if [ -z "$API_KEY" ]; then
    echo "CRITICAL ERROR: Could not retrieve API key. Setup failed."
    exit 1
fi

echo "API Key retrieved."

# 3. Create Scenario Data using Python
# We create 1 Problem and 5 Requests via API
cat > /tmp/create_scenario.py << PYEOF
import requests
import json
import sys

API_KEY = "$API_KEY"
BASE_URL = "http://localhost:8080/api/v3"
HEADERS = {
    "TECHNICIAN_KEY": API_KEY,
    "Content-Type": "application/x-www-form-urlencoded"
}

def create_request(subject, description):
    input_data = {
        "request": {
            "subject": subject,
            "description": description,
            "priority": {"name": "Normal"},
            "requester": {"name": "Administrator"}
        }
    }
    data = {"input_data": json.dumps(input_data)}
    try:
        resp = requests.post(f"{BASE_URL}/requests", headers=HEADERS, data=data, verify=False)
        if resp.status_code in [200, 201]:
            json_resp = resp.json()
            # Handle different API response structures
            if 'request' in json_resp:
                return json_resp['request']['id']
            elif 'response_status' in json_resp and json_resp['response_status']['status_code'] == 2000:
                 # Some versions wrap differently
                 return json_resp['request']['id']
            print(f"Error creating request: {resp.text}")
    except Exception as e:
        print(f"Exception creating request: {e}")
    return None

def create_problem(title, description):
    input_data = {
        "problem": {
            "title": title,
            "description": description,
            "impact": {"name": "High"},
            "urgency": {"name": "High"}
        }
    }
    data = {"input_data": json.dumps(input_data)}
    try:
        resp = requests.post(f"{BASE_URL}/problems", headers=HEADERS, data=data, verify=False)
        if resp.status_code in [200, 201]:
            json_resp = resp.json()
            if 'problem' in json_resp:
                return json_resp['problem']['id']
            print(f"Error creating problem: {resp.text}")
    except Exception as e:
        print(f"Exception creating problem: {e}")
    return None

# Scenario Data
scenario = {
    "problem_id": None,
    "target_request_ids": [],
    "distractor_request_ids": []
}

print("Creating Problem record...")
pid = create_problem("Global VPN Gateway Connection Failure", "All users reporting inability to connect via VPN.")
if pid:
    scenario["problem_id"] = pid
    print(f"Created Problem ID: {pid}")

print("Creating Requests...")
# Targets
r1 = create_request("Unable to connect to VPN from home", "Connection times out.")
r2 = create_request("VPN Error 619 when dialing in", "Getting error 619 constantly.")
r3 = create_request("Cannot access internal file server via VPN", "VPN connects but no file access.")

if r1: scenario["target_request_ids"].append(r1)
if r2: scenario["target_request_ids"].append(r2)
if r3: scenario["target_request_ids"].append(r3)

# Distractors
d1 = create_request("Printer on 2nd floor is jamming", "Paper jam in tray 2.")
d2 = create_request("Need password reset for SAP", "Locked out of account.")

if d1: scenario["distractor_request_ids"].append(d1)
if d2: scenario["distractor_request_ids"].append(d2)

# Save ID map for verification
with open("/tmp/scenario_ids.json", "w") as f:
    json.dump(scenario, f)

print(f"Scenario created: {scenario}")
PYEOF

echo "Running scenario creation script..."
python3 /tmp/create_scenario.py

# 4. Open Firefox to Problems List
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Problem.do" # Direct to Problems module

# 5. Capture Initial State
sleep 5
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png ga

echo "=== Setup Complete ==="