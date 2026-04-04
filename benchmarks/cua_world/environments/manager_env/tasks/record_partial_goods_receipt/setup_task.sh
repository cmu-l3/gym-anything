#!/bin/bash
# Setup script for record_partial_goods_receipt task
# Creates a specific Purchase Order (PO-8842) for Exotic Liquids with Boston Crab Meat

set -e
echo "=== Setting up record_partial_goods_receipt task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Manager is running
wait_for_manager 60

# 2. Record task start timestamp
date +%s > /tmp/task_start_time.txt

# 3. Prepare data via Python script to handle UUIDs and JSON complexity
#    We use a python helper here because managing Manager.io UUID references in bash is error-prone
cat > /tmp/setup_po_data.py << 'PYEOF'
import requests
import re
import sys
import json
import uuid

MANAGER_URL = "http://localhost:8080"
COOKIES = {}

def get_session():
    s = requests.Session()
    # Login
    r = s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    return s

def get_business_key(s):
    r = s.get(f"{MANAGER_URL}/businesses")
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', r.text)
    return m.group(1) if m else None

def get_form_key(s, biz_key, endpoint):
    # Manager uses a hidden input name that acts as a key for the form
    r = s.get(f"{MANAGER_URL}/{endpoint}?{biz_key}")
    # Look for input name="[UUID]" value="{}"
    m = re.search(r'name="([a-f0-9-]+)" value="\{', r.text)
    return m.group(1) if m else "febb4049-dcdb-4c7a-a395-4b71da72a85b" # fallback

def create_item(s, biz_key, name):
    # Check if exists
    r = s.get(f"{MANAGER_URL}/inventory-items?{biz_key}.json") # Try JSON endpoint if available
    # Fallback to scraping or just Create New (Manager allows dupes, but we try to avoid)
    
    # Create
    form_key = get_form_key(s, biz_key, "inventory-item-form")
    item_uuid = str(uuid.uuid4())
    payload = {
        "Name": name,
        "ItemCode": "BCM-001",
        "PurchasePrice": 10,
        "SalesPrice": 20
    }
    data = {form_key: json.dumps(payload)}
    s.post(f"{MANAGER_URL}/inventory-item-form?{biz_key}", data=data)
    
    # We need to find the UUID of the item we just made/exists
    # This is tricky without API documentation, but we'll search the list page
    r = s.get(f"{MANAGER_URL}/inventory-items?{biz_key}")
    # Regex to find the key for the item. Link looks like: inventory-item-form?Key=[UUID]&...
    # We search for the name, then find the closest preceding link
    # This is rough scraping.
    for line in r.text.split('\n'):
        if name in line:
            # Re-read list to find key map
            pass
            
    # BETTER STRATEGY: Get the UUID from the list JSON if available, or just rely on name matching for the PO if Manager supports it?
    # Manager internal storage uses UUIDs.
    # For this setup script, we will iterate the list page to find UUIDs.
    return find_uuid_by_name(s, biz_key, "inventory-items", name)

def get_supplier_uuid(s, biz_key, name):
    return find_uuid_by_name(s, biz_key, "suppliers", name)

def find_uuid_by_name(s, biz_key, endpoint, name):
    r = s.get(f"{MANAGER_URL}/{endpoint}?{biz_key}")
    # Pattern: <td ...>Name</td> ... <a href="...Key=UUID...">Edit</a>
    # or <div ...>Name</div>
    # We'll split by the name, then look backwards for the Key
    if name not in r.text:
        return None
    
    # Extract all keys and names roughly
    # Manager URLs: /supplier-form?Key=88f9...&FileID=...
    parts = r.text.split(name)
    before = parts[0]
    # Look for last occurrence of Key=([a-f0-9-]+)
    keys = re.findall(r'Key=([a-f0-9-]+)', before)
    if keys:
        return keys[-1]
    return None

def main():
    try:
        s = get_session()
        biz_key = get_business_key(s)
        if not biz_key:
            print("Error: Northwind Traders not found")
            sys.exit(1)
            
        print(f"Business Key: {biz_key}")
        
        # 1. Ensure Inventory Item "Boston Crab Meat"
        item_uuid = create_item(s, biz_key, "Boston Crab Meat")
        if not item_uuid:
            print("Creating Boston Crab Meat...")
            # Create logic
            form_key = get_form_key(s, biz_key, "inventory-item-form")
            payload = {"Name": "Boston Crab Meat", "ItemCode": "BCM-001"}
            s.post(f"{MANAGER_URL}/inventory-item-form?{biz_key}", data={form_key: json.dumps(payload)})
            item_uuid = find_uuid_by_name(s, biz_key, "inventory-items", "Boston Crab Meat")
            
        print(f"Item UUID: {item_uuid}")

        # 2. Ensure Supplier "Exotic Liquids"
        supp_uuid = get_supplier_uuid(s, biz_key, "Exotic Liquids")
        if not supp_uuid:
            print("Creating Exotic Liquids...")
            form_key = get_form_key(s, biz_key, "supplier-form")
            payload = {"Name": "Exotic Liquids"}
            s.post(f"{MANAGER_URL}/supplier-form?{biz_key}", data={form_key: json.dumps(payload)})
            supp_uuid = get_supplier_uuid(s, biz_key, "Exotic Liquids")
            
        print(f"Supplier UUID: {supp_uuid}")
        
        # 3. Create Purchase Order PO-8842
        # Check if exists first
        po_uuid = find_uuid_by_name(s, biz_key, "purchase-orders", "PO-8842")
        if not po_uuid:
            print("Creating PO-8842...")
            form_key = get_form_key(s, biz_key, "purchase-order-form")
            # Structure for lines:
            lines = []
            if item_uuid:
                lines.append({
                    "Item": item_uuid,
                    "Qty": 40,
                    "UnitPrice": 15
                })
            
            payload = {
                "Reference": "PO-8842",
                "IssueDate": "2026-03-01", # valid date
                "Supplier": supp_uuid,
                "Lines": lines,
                "Description": "Urgent order for crab meat"
            }
            
            resp = s.post(f"{MANAGER_URL}/purchase-order-form?{biz_key}", data={form_key: json.dumps(payload)})
            if resp.status_code == 200:
                print("Purchase Order created successfully.")
            else:
                print(f"Failed to create PO: {resp.status_code}")
        else:
            print("PO-8842 already exists.")
            
    except Exception as e:
        print(f"Setup failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
PYEOF

# 4. Run the python data setup
python3 /tmp/setup_po_data.py

# 5. Open Firefox at the Purchase Orders page
# Using the helper function to ensure clean start
echo "Opening Manager.io at Purchase Orders..."
open_manager_at "purchase_orders"

# 6. Capture initial state
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="