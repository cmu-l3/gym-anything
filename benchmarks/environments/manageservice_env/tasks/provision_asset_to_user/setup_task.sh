#!/bin/bash
# Setup script for provision_asset_to_user
# Ensures SDP is running, creates necessary initial data (User, Dept, Asset),
# and launches Firefox.

set -e
echo "=== Setting up Provision Asset Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure SDP is running
ensure_sdp_running

# 2. Generate/Get API Key for setup
echo "Getting API key..."
API_KEY=$(get_sdp_api_key_from_db)
if [ -z "$API_KEY" ]; then
    echo "API key not found in DB, generating via web login..."
    write_python_login_script
    generate_api_key_via_web
    API_KEY=$(get_sdp_api_key_from_db)
fi

echo "Using API Key: ${API_KEY:0:5}..."

# 3. Create Initial Data using Python + API
# We need: Department 'Operations', User 'Elena Fisher', Product 'Laptop', Asset 'WS-LPT-4402'
cat > /tmp/setup_data.py << PYEOF
import requests
import json
import sys

BASE_URL = "http://localhost:8080/api/v3"
HEADERS = {
    "TECHNICIAN_KEY": "$API_KEY",
    "Accept": "application/vnd.manageengine.sdp.v3+json"
}

def check_exists(endpoint, name_key, name_val):
    try:
        url = f"{BASE_URL}/{endpoint}"
        params = {"input_data": json.dumps({"list_info": {"search_criteria": {"field": "name", "condition": "is", "value": name_val}}})}
        r = requests.get(url, headers=HEADERS, params=params, verify=False)
        if r.status_code == 200:
            data = r.json()
            if data.get(endpoint) and len(data[endpoint]) > 0:
                return data[endpoint][0]
    except Exception as e:
        print(f"Check failed for {endpoint}: {e}")
    return None

def create_obj(endpoint, payload_key, data):
    try:
        url = f"{BASE_URL}/{endpoint}"
        payload = {"input_data": {payload_key: data}}
        r = requests.post(url, headers=HEADERS, data={"input_data": json.dumps(payload["input_data"])}, verify=False)
        if r.status_code in [200, 201]:
            print(f"Created {payload_key}: {data.get('name')}")
            return r.json().get(payload_key)
        else:
            print(f"Failed to create {payload_key}: {r.text}")
    except Exception as e:
        print(f"Error creating {payload_key}: {e}")
    return None

# 1. Create Department
dept = check_exists("departments", "name", "Operations")
if not dept:
    dept = create_obj("departments", "department", {"name": "Operations", "description": "Operations Dept"})

# 2. Create User
user = check_exists("users", "name", "Elena Fisher")
if not user:
    user_data = {"name": "Elena Fisher", "employee_id": "EMP001"}
    if dept:
        user_data["department"] = {"id": dept.get("id")}
    user = create_obj("users", "user", user_data)

# 3. Create Product Type (Laptop) if needed - usually assumes some exist
# We'll check for a product type "Workstation" or create one
product_type = check_exists("product_types", "name", "Workstation")
if not product_type:
    # Try to just use existing or create
    product_type = create_obj("product_types", "product_type", {"name": "Workstation", "type": "Asset"})

# 4. Create Product
product = check_exists("products", "name", "Dell Latitude")
if not product:
    prod_data = {"name": "Dell Latitude", "manufacturer": "Dell"}
    if product_type:
        prod_data["product_type"] = {"id": product_type.get("id")}
    product = create_obj("products", "product", prod_data)

# 5. Create Asset
asset = check_exists("assets", "name", "WS-LPT-4402")
if not asset:
    asset_data = {
        "name": "WS-LPT-4402",
        "state": {"name": "In Store"}, # Starting state
        "description": "Initial inventory scan."
    }
    if product:
        asset_data["product"] = {"id": product.get("id")}
    
    # Need to be careful with asset endpoint, sometimes it's /assets or /hardware
    # Try generic asset creation
    create_obj("assets", "asset", asset_data)

print("Data setup complete.")
PYEOF

echo "Running data setup script..."
python3 /tmp/setup_data.py > /tmp/setup_data.log 2>&1 || echo "Warning: Data setup script had errors"

# 4. Launch Firefox
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 5. Record Start Time & Initial Screenshot
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="