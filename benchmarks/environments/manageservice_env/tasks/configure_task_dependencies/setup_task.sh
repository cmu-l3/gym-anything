#!/bin/bash
# Setup for "configure_task_dependencies" task
# Creates a Service Request with 4 unlinked tasks via API

echo "=== Setting up Task Dependencies task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure ServiceDesk Plus is running
ensure_sdp_running

# 2. Get API Key (Administrator)
echo "Retrieving API Key..."
API_KEY=$(get_sdp_api_key_from_db)

if [ -z "$API_KEY" ]; then
    echo "API Key not found in DB. Attempting generation via web login..."
    generate_api_key_via_web
    API_KEY=$(get_sdp_api_key_from_db)
fi

if [ -z "$API_KEY" ]; then
    echo "ERROR: Could not retrieve API Key. Task setup failed."
    exit 1
fi
echo "API Key retrieved."

# 3. Create Request and Tasks via Python script
echo "Creating Request and Tasks..."
cat > /tmp/create_scenario.py << PYEOF
import requests
import json
import sys

base_url = "http://localhost:8080/api/v3"
headers = {
    "TECHNICIAN_KEY": "$API_KEY",
    "Accept": "application/vnd.manageengine.sdp.v3+json",
    "Content-Type": "application/x-www-form-urlencoded"
}

def create_request():
    url = base_url + "/requests"
    data = {
        "input_data": json.dumps({
            "request": {
                "subject": "Deploy HA Web Cluster - Project Alpha",
                "description": "Project to deploy high-availability cluster. Requires coordinated task execution.",
                "requester": {"name": "Administrator"},
                "status": {"name": "Open"},
                "priority": {"name": "High"}
            }
        })
    }
    response = requests.post(url, headers=headers, data=data, verify=False)
    if response.status_code not in [200, 201]:
        print(f"Error creating request: {response.text}")
        sys.exit(1)
    return response.json()['request']['id']

def add_task(req_id, title, desc):
    url = base_url + f"/requests/{req_id}/tasks"
    data = {
        "input_data": json.dumps({
            "task": {
                "title": title,
                "description": desc,
                "status": {"name": "Open"},
                "percentage_completion": "0"
            }
        })
    }
    response = requests.post(url, headers=headers, data=data, verify=False)
    if response.status_code not in [200, 201]:
        print(f"Error creating task {title}: {response.text}")
        # Non-fatal, try continuing
    else:
        print(f"Created task: {title}")

try:
    req_id = create_request()
    print(f"REQUEST_ID={req_id}")
    
    tasks = [
        ("Provision Infrastructure", "Spin up VMs and configure networking"),
        ("Configure Database Cluster", "Install PostgreSQL and set up replication"),
        ("Configure Web Server Nodes", "Install Nginx and deploy config"),
        ("Deploy Application Artifacts", "Deploy WAR file to web servers")
    ]
    
    for title, desc in tasks:
        add_task(req_id, title, desc)
        
except Exception as e:
    print(f"Exception: {e}")
    sys.exit(1)
PYEOF

# Execute the creation script
python3 /tmp/create_scenario.py > /tmp/scenario_creation.log 2>&1
cat /tmp/scenario_creation.log

# Extract Request ID
REQUEST_ID=$(grep "REQUEST_ID=" /tmp/scenario_creation.log | cut -d'=' -f2 | tr -d '[:space:]')

if [ -z "$REQUEST_ID" ]; then
    echo "ERROR: Failed to create request. Check log."
    exit 1
fi

echo "Created Request ID: $REQUEST_ID"

# 4. Open Firefox directly to the tasks view of this request
# Note: URL format depends on SDP version, trying standard v3/v4 format
# Fallback to WorkOrder.do if v3 UI link is complex
TARGET_URL="${SDP_BASE_URL}/ManageEngine/WorkOrder.do?workOrderID=${REQUEST_ID}&operation=view"

echo "Launching Firefox..."
ensure_firefox_on_sdp "$TARGET_URL"
sleep 8

# 5. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="