#!/bin/bash
echo "=== Setting up Merge Duplicate Requests Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure SDP is running
ensure_sdp_running

# Wait for API key to be available (or generate it)
echo "Getting Administrator API Key..."
API_KEY=$(get_sdp_api_key_from_db)

if [ -z "$API_KEY" ]; then
    echo "API Key not found in DB, attempting generation via web login helper..."
    # Ensure dependencies for the login script
    pip3 install requests beautifulsoup4 >/dev/null 2>&1 || true
    write_python_login_script
    API_KEY=$(python3 /tmp/sdp_login.py)
fi

if [ -z "$API_KEY" ]; then
    echo "ERROR: Failed to obtain API Key. Cannot setup task data."
    exit 1
fi

echo "API Key obtained: ${API_KEY:0:5}..."

# Create Python script to seed data via API
cat > /tmp/seed_merge_data.py << PYEOF
import requests
import json
import sys
import time

BASE_URL = "https://localhost:8080/api/v3"
HEADERS = {
    "authtoken": "$API_KEY",
    "Content-Type": "application/vnd.manageengine.sdp.v3+json"
}

# Disable SSL warnings
requests.packages.urllib3.disable_warnings()

def create_requester(name, email, department):
    url = f"{BASE_URL}/users"
    data = {
        "user": {
            "name": name,
            "email_id": email,
            "department": {"name": department} if department else None,
            "is_requester": True
        }
    }
    # Check if exists first (simple check)
    # Ideally search, but for setup just try create
    try:
        resp = requests.post(url, headers=HEADERS, data=json.dumps(data, default=str), verify=False)
        if resp.status_code in [200, 201]:
            print(f"Created user: {name}")
            return resp.json().get("user", {}).get("id")
        else:
            print(f"Failed to create user {name}: {resp.text}")
            return None
    except Exception as e:
        print(f"Error creating user {name}: {e}")
        return None

def create_request(subject, description, requester_name):
    url = f"{BASE_URL}/requests"
    data = {
        "request": {
            "subject": subject,
            "description": description,
            "requester": {"name": requester_name},
            "status": {"name": "Open"},
            "priority": {"name": "High"} if "server" in subject.lower() else {"name": "Normal"}
        }
    }
    input_data = {"input_data": data} # V3 format often requires input_data wrapper or raw structure depending on endpoint version
    
    # Try standard V3 structure
    try:
        resp = requests.post(url, headers=HEADERS, json=data, verify=False)
        if resp.status_code not in [200, 201]:
             # Try legacy/alt structure just in case
             resp = requests.post(url, headers=HEADERS, data={"input_data": json.dumps(data)}, verify=False)

        if resp.status_code in [200, 201]:
            req = resp.json().get("request", {})
            print(f"Created request {req.get('id')}: {subject[:30]}...")
            return req.get("id")
        else:
            print(f"Failed to create request '{subject}': {resp.text}")
            return None
    except Exception as e:
        print(f"Error creating request: {e}")
        return None

# 1. Create Requesters (Departments might need to exist, defaulting to None if strict)
# We assume standard departments might not exist, so we skip department in creation to be safe,
# or user creation handles it.
requesters = [
    ("Sarah Johnson", "sarah.johnson@company.com", "Accounting"),
    ("Mike Chen", "mike.chen@company.com", "Engineering"),
    ("Lisa Rodriguez", "lisa.rodriguez@company.com", "Marketing"),
    ("David Thompson", "david.thompson@company.com", "Sales")
]

for name, email, dept in requesters:
    create_requester(name, email, None) # Skip department to avoid error if dept doesn't exist

# 2. Create Requests
requests_data = [
    {
        "role": "parent",
        "requester": "Sarah Johnson",
        "subject": "Email server completely down - cannot send or receive",
        "desc": "Since approximately 7:00 AM this morning, our email system has been completely non-functional..."
    },
    {
        "role": "child",
        "requester": "Mike Chen",
        "subject": "Outlook keeps showing disconnected from server since 7 AM",
        "desc": "My Outlook client has been showing 'Disconnected' in the bottom status bar..."
    },
    {
        "role": "child",
        "requester": "Lisa Rodriguez",
        "subject": "Unable to access email since this morning - urgent",
        "desc": "Good morning, I haven't been able to access my email since I arrived at the office..."
    },
    {
        "role": "child",
        "requester": "David Thompson",
        "subject": "Exchange server error - email not working for entire Sales team",
        "desc": "Reporting a major email outage affecting the entire Sales department..."
    }
]

result_map = {}

for item in requests_data:
    req_id = create_request(item["subject"], item["desc"], item["requester"])
    if req_id:
        if item["role"] == "parent":
            result_map["parent_id"] = req_id
            result_map["parent_subject"] = item["subject"]
        else:
            if "child_ids" not in result_map:
                result_map["child_ids"] = []
            result_map["child_ids"].append(req_id)

# Save map
with open("/tmp/task_requests.json", "w") as f:
    json.dump(result_map, f, indent=2)

print("Seed complete.")
PYEOF

# Run the seeding script
echo "Seeding data..."
python3 /tmp/seed_merge_data.py

# Verify seed success
if [ ! -f "/tmp/task_requests.json" ]; then
    echo "ERROR: Data seeding failed, requests map not found."
    # Fallback: We proceed, but verification might fail if data isn't there.
    # We'll try to rely on subject matching in export if IDs are missing.
else
    echo "Data seeded successfully:"
    cat /tmp/task_requests.json
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch Firefox to the Requests view
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"

# Take initial screenshot
sleep 8
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="