#!/bin/bash
set -e
echo "=== Setting up Bulk Dispose Assets task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for SDP to be fully running
ensure_sdp_running

# 2. Get API Key for asset creation
echo "Retrieving API Key..."
API_KEY=$(get_sdp_api_key_from_db)

# If no key found, try to generate one via web login or use default/fallback
if [ -z "$API_KEY" ]; then
    echo "No API key found in DB. Attempting to generate via web..."
    generate_api_key_via_web
    API_KEY=$(get_sdp_api_key_from_db)
fi

if [ -z "$API_KEY" ]; then
    echo "WARNING: Could not retrieve API Key. Asset creation might fail if not done via DB injection."
    # We will try DB injection as fallback if API fails, but Python script below uses API
fi

# 3. Create the target assets using Python script
# We use Python to handle the API calls cleanly
cat > /tmp/create_legacy_assets.py << PYEOF
import requests
import json
import sys
import time

# SDP Configuration
base_url = "http://localhost:8080/api/v3/assets"
headers = {
    "TECHNICIAN_KEY": "$API_KEY",
    "Content-Type": "application/x-www-form-urlencoded"
}

assets_to_create = ["OLD-PC-01", "OLD-PC-02", "OLD-PC-03", "OLD-PC-04", "OLD-PC-05"]
target_state = "In Store"
product_type = "Workstation"

print(f"Creating {len(assets_to_create)} assets...")

for name in assets_to_create:
    # Construct input_data JSON
    # Note: Structure depends on SDP version, v3 uses input_data parameter
    data = {
        "asset": {
            "name": name,
            "product": {"name": product_type},
            "state": {"name": target_state},
            "site": {"name": "Not Associated"} # Default site
        }
    }
    
    payload = {"input_data": json.dumps(data)}
    
    try:
        # Check if exists first (optional, but good for idempotency)
        # For simplicity, we just try to create. SDP allows dupes depending on config,
        # but usually unique name.
        
        # POST to create
        response = requests.post(base_url, headers=headers, data=payload, verify=False)
        
        if response.status_code in [200, 201]:
            resp_json = response.json()
            if resp_json.get("response_status", {}).get("status") == "success":
                print(f"Created {name}: Success")
            else:
                print(f"Created {name}: API returned {resp_json.get('response_status', {}).get('status')}")
                # Fallback: Maybe it already exists?
        else:
            print(f"Failed to create {name}: HTTP {response.status_code} - {response.text}")
            
    except Exception as e:
        print(f"Error creating {name}: {str(e)}")

print("Asset creation process finished.")
PYEOF

echo "Running asset creation script..."
python3 /tmp/create_legacy_assets.py > /tmp/asset_creation.log 2>&1 || echo "Python script failed"

# 4. Verify assets exist in DB (Fallback / Confirmation)
echo "Verifying assets in database..."
ASSET_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM resources WHERE resourcename LIKE 'OLD-PC-%';")
echo "Found $ASSET_COUNT assets matching 'OLD-PC-%'"

if [ "$ASSET_COUNT" -lt 5 ]; then
    echo "WARNING: Less than 5 assets found. Injecting via SQL as fallback..."
    # SQL injection fallback if API failed (SDP database schema assumptions)
    # Get ID for 'In Store' state
    STATE_ID=$(sdp_db_exec "SELECT resourcestateid FROM resourcestate WHERE displaystate = 'In Store' LIMIT 1;")
    # Get ID for 'Workstation' product/type (simplified assumption)
    # This is risky without knowing exact schema IDs, but we'll try basic insert if needed
    # For now, we assume the API worked or the environment provided them.
    # If this fails, the task will likely fail verification, which is acceptable for setup failure.
fi

# 5. Open Firefox to the Assets module
echo "Launching Firefox to Assets module..."
ensure_firefox_on_sdp "http://localhost:8080/ManageEngine/AssetList.do"

# 6. Capture initial state
sleep 5
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="