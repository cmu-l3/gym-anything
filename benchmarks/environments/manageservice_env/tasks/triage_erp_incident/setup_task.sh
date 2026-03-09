#!/bin/bash
echo "=== Setting up Triage ERP Incident Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure SDP is running
ensure_sdp_running

# 2. Python script to setup data (Category, Group, Ticket) via API
# We do this via Python to handle authentication and JSON cleanly
cat > /tmp/setup_triage_data.py << 'PYEOF'
import sys
import json
import requests
import time

# Disable warnings
from urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

BASE_URL = "https://localhost:8080"
API_V3 = f"{BASE_URL}/api/v3"

# We need an API key. We'll try to get it from DB or generate it.
# For simplicity in this script, we assume the helper in task_utils 
# has generated one or we can fetch it from the DB.
# In a real scenario, we might scrape the web login to generate a key.

def get_api_key():
    # Try to read from a file if task_utils saved it, or query DB
    # For now, let's use the DB query command via shell wrapper if needed
    # But here we are in python. Let's assume the setup wrapper passed it 
    # or we can find it.
    pass

# Simplified: we will rely on the setup_task.sh to provide the key 
# via environment variable or file.
try:
    with open('/tmp/sdp_api_key.txt', 'r') as f:
        API_KEY = f.read().strip()
except:
    print("No API Key found")
    sys.exit(1)

HEADERS = {
    "TECHNICIAN_KEY": API_KEY,
    "Accept": "application/vnd.manageengine.sdp.v3+json"
}

def create_category():
    data = {
        "category": {
            "name": "Enterprise Applications",
            "description": "ERP, CRM, and other enterprise software"
        }
    }
    # Check if exists first
    r = requests.get(f"{API_V3}/categories", headers=HEADERS, verify=False)
    if r.status_code == 200:
        for cat in r.json().get('categories', []):
            if cat['name'] == "Enterprise Applications":
                print("Category exists")
                return cat['id']
    
    # Create
    r = requests.post(f"{API_V3}/categories", headers=HEADERS, data={'input_data': json.dumps(data)}, verify=False)
    if r.status_code in [200, 201]:
        print("Category created")
        return r.json()['category']['id']
    print(f"Failed to create category: {r.text}")
    return None

def create_subcategory(cat_id):
    if not cat_id: return
    data = {
        "subcategory": {
            "name": "Payroll",
            "category": {"id": cat_id}
        }
    }
    # List subcategories
    r = requests.get(f"{API_V3}/subcategories?category={cat_id}", headers=HEADERS, verify=False)
    if r.status_code == 200:
        for sub in r.json().get('subcategories', []):
            if sub['name'] == "Payroll":
                print("Subcategory exists")
                return
    
    # Create
    r = requests.post(f"{API_V3}/subcategories", headers=HEADERS, data={'input_data': json.dumps(data)}, verify=False)
    print(f"Subcategory creation: {r.status_code}")

def create_group():
    data = {
        "group": {
            "name": "ERP Support",
            "description": "Level 2/3 support for ERP systems"
        }
    }
    r = requests.get(f"{API_V3}/groups", headers=HEADERS, verify=False)
    if r.status_code == 200:
        for g in r.json().get('groups', []):
            if g['name'] == "ERP Support":
                print("Group exists")
                return
    
    r = requests.post(f"{API_V3}/groups", headers=HEADERS, data={'input_data': json.dumps(data)}, verify=False)
    print(f"Group creation: {r.status_code}")

def create_requester():
    # Create Sarah Jenkins
    data = {
        "requester": {
            "name": "Sarah Jenkins",
            "email_id": "sarah.jenkins@example.com"
        }
    }
    r = requests.post(f"{API_V3}/requesters", headers=HEADERS, data={'input_data': json.dumps(data)}, verify=False)
    print(f"Requester creation: {r.status_code}")

def create_request():
    # Check if request exists
    r = requests.get(f"{API_V3}/requests?subject=Urgent: Payroll export failing", headers=HEADERS, verify=False)
    if r.status_code == 200 and r.json().get('requests'):
        print("Request already exists")
        return

    data = {
        "request": {
            "subject": "Urgent: Payroll export failing",
            "description": "I am trying to export the Q3 payroll CSV for the board meeting tomorrow morning, but it keeps giving me a timeout error. I've tried 3 times. Please help, this is critical.",
            "requester": {"name": "Sarah Jenkins"},
            "priority": {"name": "Normal"}, # Start with Normal, agent must change to High
            "status": {"name": "Open"}
        }
    }
    r = requests.post(f"{API_V3}/requests", headers=HEADERS, data={'input_data': json.dumps(data)}, verify=False)
    print(f"Request creation: {r.status_code}")
    if r.status_code != 200:
        print(r.text)

cat_id = create_category()
create_subcategory(cat_id)
create_group()
create_requester()
create_request()
PYEOF

# Get/Generate API Key using helper
log "Getting API Key..."
API_KEY=$(get_sdp_api_key_from_db)
if [ -z "$API_KEY" ]; then
    log "Generating API key via web..."
    ensure_sdp_running # Ensures web is up
    write_python_login_script
    generate_api_key_via_web > /tmp/api_key_gen.log 2>&1
    API_KEY=$(get_sdp_api_key_from_db)
fi

if [ -n "$API_KEY" ]; then
    echo "$API_KEY" > /tmp/sdp_api_key.txt
    # Run the setup script
    python3 /tmp/setup_triage_data.py
else
    log "ERROR: Could not get API key. Setup might fail."
fi

# 3. Launch Firefox to the requests view
log "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"

# 4. Record task start
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="