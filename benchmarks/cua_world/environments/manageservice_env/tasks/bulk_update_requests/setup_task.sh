#!/bin/bash
set -e
echo "=== Setting up Bulk Update Requests task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure SDP is running (this waits for install if needed)
ensure_sdp_running

# Wait for API availability
wait_for_sdp_https 600

# Generate/Get API Key
echo "Retrieving API Key..."
API_KEY=$(get_sdp_api_key_from_db)

if [ -z "$API_KEY" ]; then
    echo "API Key not found in DB, attempting to generate via Login..."
    write_python_login_script
    generate_api_key_via_web
    API_KEY=$(get_sdp_api_key_from_db)
fi

if [ -z "$API_KEY" ]; then
    echo "ERROR: Could not retrieve API Key. Setup failed."
    exit 1
fi

echo "API Key retrieved."

# Create Python script to populate data via API
cat > /tmp/setup_data.py << PYEOF
import requests
import json
import sys
import random

BASE_URL = "https://localhost:8080/api/v3"
HEADERS = {
    "TECHNICIAN_KEY": "$API_KEY",
    "Accept": "application/vnd.manageengine.sdp.v3+json"
}

# Disable SSL warnings
requests.packages.urllib3.disable_warnings()

def create_group(name):
    data = {"group": {"name": name, "description": "Specialized support team"}}
    resp = requests.post(f"{BASE_URL}/groups", data={"input_data": json.dumps(data)}, headers=HEADERS, verify=False)
    if resp.status_code in [200, 201]:
        return resp.json().get("group", {}).get("id")
    # If exists, try to find it (API might return error if exists)
    return None

def create_category(name):
    data = {"category": {"name": name}}
    resp = requests.post(f"{BASE_URL}/categories", data={"input_data": json.dumps(data)}, headers=HEADERS, verify=False)
    if resp.status_code in [200, 201]:
        return resp.json().get("category", {}).get("id")
    return None

def create_subcategory(name, category_id):
    data = {"subcategory": {"name": name, "category": {"id": category_id}}}
    resp = requests.post(f"{BASE_URL}/subcategories", data={"input_data": json.dumps(data)}, headers=HEADERS, verify=False)
    if resp.status_code in [200, 201]:
        return resp.json().get("subcategory", {}).get("id")
    return None

def create_request(subject):
    data = {
        "request": {
            "subject": subject,
            "description": "Reported issue with mobile workstation.",
            "status": {"name": "Open"},
            "priority": {"name": "Medium"},
            "requester": {"name": "Guest"}
        }
    }
    resp = requests.post(f"{BASE_URL}/requests", data={"input_data": json.dumps(data)}, headers=HEADERS, verify=False)
    if resp.status_code in [200, 201]:
        return resp.json().get("request", {}).get("id")
    print(f"Failed to create request: {resp.text}")
    return None

print("Creating setup data...")

# 1. Create Group
grp_id = create_group("Clinical IT Support")
print(f"Group ID: {grp_id}")

# 2. Create Category/Subcategory
cat_id = create_category("Medical Hardware")
print(f"Category ID: {cat_id}")

sub_id = None
if cat_id:
    sub_id = create_subcategory("WOW Cart", cat_id)
    print(f"Subcategory ID: {sub_id}")

# 3. Create 5 Requests
req_ids = []
issues = ["battery dead", "screen flickering", "wheel stuck", "keyboard spill", "wont turn on"]
for i in range(5):
    cart_num = random.randint(100, 199)
    subject = f"WOW Cart {cart_num} {issues[i]}"
    rid = create_request(subject)
    if rid:
        req_ids.append(rid)

print(f"Created Requests: {req_ids}")

# Save IDs to file for export script
with open("/tmp/target_req_ids.json", "w") as f:
    json.dump(req_ids, f)

PYEOF

# Run data setup
python3 /tmp/setup_data.py

# Launch Firefox to Request List
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"

# Maximize and focus
sleep 5
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="