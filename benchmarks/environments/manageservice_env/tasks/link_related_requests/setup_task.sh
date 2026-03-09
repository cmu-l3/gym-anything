#!/bin/bash
# Setup script for link_related_requests task

echo "=== Setting up Link Related Requests task ==="
source /workspace/scripts/task_utils.sh

# 1. Ensure SDP is running
ensure_sdp_running
clear_mandatory_password_change

# 2. Get API Key to create requests
API_KEY=$(get_sdp_api_key_from_db)

if [ -z "$API_KEY" ]; then
    echo "Generating API key via web login..."
    # Ensure python script is available
    write_python_login_script
    # Run login script to generate key
    generate_api_key_via_web
    sleep 5
    API_KEY=$(get_sdp_api_key_from_db)
fi

if [ -z "$API_KEY" ]; then
    echo "ERROR: Failed to obtain API key. Cannot create requests."
    # Fallback: We rely on the agent to create them? No, task requires existing requests.
    # Try one more method: Insert directly into DB? Too complex.
    # We will proceed, hoping the python script worked.
    exit 1
fi

echo "API Key obtained."

# 3. Create Requests via API
# We use a simple Python script to make the API calls to avoid complex curl escaping
cat > /tmp/create_requests.py << PYEOF
import requests
import json
import sys

api_key = "$API_KEY"
base_url = "http://localhost:8080/api/v3/requests"

headers = {
    "TECHNICIAN_KEY": api_key,
    "Content-Type": "application/x-www-form-urlencoded"
}

def create_request(subject, description, priority):
    data = {
        "request": {
            "subject": subject,
            "description": description,
            "priority": {"name": priority},
            "requester": {"name": "Administrator"},
            "status": {"name": "Open"}
        }
    }
    payload = {"input_data": json.dumps(data)}
    try:
        response = requests.post(base_url, headers=headers, data=payload, verify=False)
        if response.status_code in [200, 201]:
            resp_json = response.json()
            if resp_json.get("response_status", {}).get("status_code") == 2000:
                req_id = resp_json.get("request", {}).get("id")
                print(f"CREATED:{req_id}")
                return req_id
    except Exception as e:
        sys.stderr.write(f"Error creating request: {e}\n")
    return None

# Request A
id_a = create_request(
    "VPN connection drops intermittently for Building A users",
    "Since Monday morning, approx 15 users in Building A have reported intermittent VPN disconnections. Impacting finance team.",
    "High"
)

# Request B
id_b = create_request(
    "Unable to establish VPN tunnel from Building A conference rooms",
    "Users in Building A conference rooms (A201, A205) cannot establish VPN tunnels via ethernet. Error: unsuccessful domain name resolution.",
    "Medium"
)

if id_a and id_b:
    with open("/tmp/task_request_ids.txt", "w") as f:
        f.write(f"{id_a}\n{id_b}\n")
else:
    sys.exit(1)
PYEOF

echo "Creating requests..."
python3 /tmp/create_requests.py > /tmp/create_req_output.txt 2>&1

if [ ! -f /tmp/task_request_ids.txt ]; then
    echo "Failed to create requests. Output:"
    cat /tmp/create_req_output.txt
    exit 1
fi

REQ_A=$(head -1 /tmp/task_request_ids.txt)
REQ_B=$(tail -1 /tmp/task_request_ids.txt)

echo "Created Request A: $REQ_A"
echo "Created Request B: $REQ_B"

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch Firefox to Login Page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# 6. Capture initial state
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="