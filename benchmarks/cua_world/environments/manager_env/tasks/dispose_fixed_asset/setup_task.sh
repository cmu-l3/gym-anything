#!/bin/bash
# Setup script for dispose_fixed_asset task
# Creates a specific Fixed Asset ("Ford Transit 2018") via API so the agent has something to dispose.

set -e

echo "=== Setting up dispose_fixed_asset task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is running
wait_for_manager 60

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_disposal_status.txt

# Python script to setup the specific data state
# 1. Enable Fixed Assets tab
# 2. Create the Asset
python3 -c '
import requests
import re
import sys
import json

BASE_URL = "http://localhost:8080"
SESSION = requests.Session()

def get_business_key():
    # Login first
    SESSION.post(f"{BASE_URL}/login", data={"Username": "administrator"})
    
    # Get businesses page
    resp = SESSION.get(f"{BASE_URL}/businesses")
    
    # Extract key for Northwind Traders
    # Looking for href="start?KEY" or similar
    match = re.search(r"start\?([^\"]+)\".*?Northwind Traders", resp.text, re.DOTALL)
    if not match:
        # Fallback to any key if specific name not found (though setup_manager should have created it)
        match = re.search(r"start\?([^\"]+)", resp.text)
    
    if match:
        return match.group(1)
    return None

def enable_fixed_assets(biz_key):
    # Get tabs form to find the correct field name
    resp = SESSION.get(f"{BASE_URL}/tabs-form?{biz_key}")
    
    # Extract the UUID field name for the JSON payload
    # name="cb09e1..." value="{...}"
    match = re.search(r"name=\"([a-f0-9-]+)\" value=\"{", resp.text)
    if not match:
        print("Could not find tabs field name")
        return False
        
    field_name = match.group(1)
    
    # We need to preserve existing tabs and add FixedAssets
    # Quick hack: just enable the set we need. Manager usually merges or we can try to parse the value.
    # For safety in this environment, we will enable a standard set.
    tabs_config = {
        "FixedAssets": True,
        "BankAndCashAccounts": True,
        "Receipts": True,
        "Payments": True, 
        "Customers": True,
        "SalesInvoices": True,
        "Suppliers": True,
        "InventoryItems": True
    }
    
    payload = {
        field_name: json.dumps(tabs_config)
    }
    
    post_resp = SESSION.post(f"{BASE_URL}/tabs-form?{biz_key}", data=payload)
    return post_resp.status_code in [200, 302, 303]

def create_asset(biz_key):
    # First, check if it exists
    list_resp = SESSION.get(f"{BASE_URL}/fixed-assets?{biz_key}")
    if "Ford Transit 2018" in list_resp.text:
        print("Asset already exists")
        # Extract UUID for later verification reference
        # <td data-key="UUID">
        # This might be hard to regex perfectly, but let attempt to find the edit link
        # <a href="fixed-asset-form?Key=UUID&...">
        match = re.search(r"fixed-asset-form\?Key=([a-f0-9-]+).+?Ford Transit 2018", list_resp.text)
        if match:
            with open("/tmp/asset_uuid.txt", "w") as f:
                f.write(match.group(1))
        return

    # Get the form field name
    form_resp = SESSION.get(f"{BASE_URL}/fixed-asset-form?{biz_key}")
    match = re.search(r"name=\"([a-f0-9-]+)\" value=\"{", form_resp.text)
    if not match:
        print("Could not find asset form field name")
        return
        
    field_name = match.group(1)
    
    # Create the asset
    asset_data = {
        "Name": "Ford Transit 2018",
        "Code": "FA-005",
        "AcquisitionCost": 15000,
        "DepreciationMethod": "StraightLine",
        "DepreciationRate": 20
    }
    
    payload = {
        field_name: json.dumps(asset_data)
    }
    
    post_resp = SESSION.post(f"{BASE_URL}/fixed-asset-form?{biz_key}", data=payload)
    print(f"Create asset status: {post_resp.status_code}")
    
    # Find the UUID of the newly created asset
    list_resp = SESSION.get(f"{BASE_URL}/fixed-assets?{biz_key}")
    match = re.search(r"fixed-asset-form\?Key=([a-f0-9-]+).+?Ford Transit 2018", list_resp.text)
    if match:
        with open("/tmp/asset_uuid.txt", "w") as f:
            f.write(match.group(1))

def main():
    key = get_business_key()
    if not key:
        print("Error: Could not find business key")
        sys.exit(1)
        
    with open("/tmp/biz_key.txt", "w") as f:
        f.write(key)
        
    print(f"Business Key: {key}")
    
    if enable_fixed_assets(key):
        print("Fixed Assets module enabled")
        
    create_asset(key)

if __name__ == "__main__":
    main()
'

# Open Manager directly to the Fixed Assets tab to save time
open_manager_at "fixed_assets"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="