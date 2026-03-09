#!/bin/bash
# Setup for "resolve_close_request" task
# Creates a specific incident ticket via API and prepares the environment

echo "=== Setting up Resolve/Close Request task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Ensure SDP is running
ensure_sdp_running

# 2. Get API Key for creating request
echo "Retrieving API Key..."
API_KEY=$(get_sdp_api_key_from_db)

if [ -z "$API_KEY" ]; then
    echo "API Key not found in DB, attempting generation via web login..."
    generate_api_key_via_web
    API_KEY=$(get_sdp_api_key_from_db)
fi

if [ -z "$API_KEY" ]; then
    echo "ERROR: Could not retrieve API Key. Cannot create task data."
    exit 1
fi

# 3. Create the specific request via Python/API
echo "Creating incident request..."
cat > /tmp/create_incident.py << PYEOF
import requests
import sys
import json
import time

url = "http://localhost:8080/api/v3/requests"
headers = {
    "TECHNICIAN_KEY": "$API_KEY",
    "Accept": "application/vnd.manageengine.sdp.v3+json"
}

input_data = {
    "request": {
        "subject": "Network connectivity down on 3rd floor",
        "description": "Multiple users on the 3rd floor are reporting inability to access network resources and internet. Approximately 45 workstations affected. Users cannot reach internal file shares, email server, or external websites. Issue started around 02:15 AM based on monitoring alerts from Nagios. Switches in IDF closet 3A appear to be functioning normally. IDF closet 3B status unknown - physical access needed.",
        "requester": {
            "name": "administrator"
        },
        "impact": {
            "name": "Affects Business"
        },
        "status": {
            "name": "Open"
        },
        "priority": {
            "name": "High"
        },
        "category": {
            "name": "Network"
        }
    }
}

files = {
    'input_data': (None, json.dumps(input_data))
}

try:
    # Try V3 API first
    response = requests.post(url, headers=headers, files=files, verify=False)
    
    if response.status_code not in [200, 201]:
        # Fallback to V1/Standard API if V3 fails (older SDP versions)
        url_v1 = "http://localhost:8080/sdpapi/request"
        params = {
            "OPERATION_NAME": "ADD_REQUEST",
            "TECHNICIAN_KEY": "$API_KEY",
            "format": "json",
            "INPUT_DATA": """
<Operation>
    <Details>
        <parameter>
            <name>subject</name>
            <value>Network connectivity down on 3rd floor</value>
        </parameter>
        <parameter>
            <name>description</name>
            <value>Multiple users on the 3rd floor are reporting inability to access network resources...</value>
        </parameter>
        <parameter>
            <name>requester</name>
            <value>administrator</value>
        </parameter>
        <parameter>
            <name>priority</name>
            <value>High</value>
        </parameter>
    </Details>
</Operation>
"""
        }
        response = requests.post(url_v1, data=params, verify=False)

    print(f"Status: {response.status_code}")
    print(f"Response: {response.text}")
    
    # Try to extract ID
    if "workorderid" in response.text.lower():
        try:
            data = response.json()
            # Handle different response structures
            if "request" in data:
                print(data["request"]["id"])
            elif "operation" in data:
                print(data["operation"]["details"]["workorderid"])
            else:
                # Regex fallback
                import re
                m = re.search(r'"id"\s*:\s*"(\d+)"', response.text)
                if m:
                    print(m.group(1))
        except:
             pass
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
PYEOF

# Run script and capture ID
REQUEST_OUTPUT=$(python3 /tmp/create_incident.py)
REQUEST_ID=$(echo "$REQUEST_OUTPUT" | tail -n 1 | tr -d ' \r\n')

# Validate Request ID
if [[ ! "$REQUEST_ID" =~ ^[0-9]+$ ]]; then
    echo "WARNING: Failed to parse Request ID from API response. Response was:"
    echo "$REQUEST_OUTPUT"
    
    # Fallback: Query DB to find the request we just tried to make
    REQUEST_ID=$(sdp_db_exec "SELECT workorderid FROM workorder WHERE title = 'Network connectivity down on 3rd floor' ORDER BY workorderid DESC LIMIT 1;")
fi

if [[ ! "$REQUEST_ID" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Could not verify request creation."
    exit 1
fi

echo "Created Request ID: $REQUEST_ID"
echo "$REQUEST_ID" > /tmp/task_request_id.txt

# 4. Open Firefox to the Requests list
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do?workOrderID=${REQUEST_ID}&operation=view"
sleep 5

# 5. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="