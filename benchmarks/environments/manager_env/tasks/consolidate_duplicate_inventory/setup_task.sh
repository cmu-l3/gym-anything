#!/bin/bash
set -e

echo "=== Setting up Consolidate Duplicate Inventory Task ==="

source /workspace/scripts/task_utils.sh

# Wait for Manager to be ready
wait_for_manager 60

# Record start time
date +%s > /tmp/task_start_time.txt

# Create the specific "messy" state using Python
# We need to:
# 1. Login/Get Session
# 2. Find/Create 'Aniseed Syrup (Old)'
# 3. Create a Sales Invoice using it
# 4. Create a Purchase Invoice using it
# 5. Output UUIDs for the verifier

cat > /tmp/setup_inventory_mess.py << 'EOF'
import requests
import re
import json
import sys

BASE_URL = "http://localhost:8080"
SESSION = requests.Session()

def get_business_key():
    # Login first
    SESSION.post(f"{BASE_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    
    # Get businesses page
    resp = SESSION.get(f"{BASE_URL}/businesses")
    
    # Find Northwind Traders key
    # Look for start?Key href associated with Northwind
    match = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
    if not match:
        # Fallback to any key if specific one not found (though Northwind is standard)
        match = re.search(r'start\?([^"&\s]+)', resp.text)
    
    if match:
        return match.group(1)
    return None

def get_form_field_name(url):
    # Manager forms use a hidden field with a UUID name to submit the JSON
    resp = SESSION.get(url)
    # Regex to find name="UUID" value="{}" or similar
    # Pattern: <input type="hidden" name="b216..." value="{}" />
    match = re.search(r'name="([a-f0-9-]+)" value="({})?"', resp.text)
    if match:
        return match.group(1)
    
    # Fallback: sometimes value is populated
    match = re.search(r'name="([a-f0-9-]+)" value="', resp.text)
    if match:
        return match.group(1)
    return None

def find_item_uuid(biz_key, item_name):
    # Scrape inventory list
    resp = SESSION.get(f"{BASE_URL}/inventory-items?{biz_key}")
    # Very rough scrape for the edit link which contains the UUID
    # <td ...>Item Name</td> ... <a href="inventory-item-form?Key=UUID&...">Edit</a>
    # We'll use a specific query if possible, but scraping is often needed in Manager's lightweight UI
    
    # Better approach: Manager often exposes .json endpoints if we accept header?
    # No, it's server-side rendered. We'll search the HTML.
    
    # Simple search for the name, then find the closest previous "Edit" link or Key
    if item_name not in resp.text:
        return None
        
    # Split by item name and look backwards for the key
    parts = resp.text.split(item_name)
    if len(parts) > 0:
        # The link is usually before the name in the table row, or inside the name cell's anchor
        # Look for inventory-item-form?Key=...
        link_match = re.search(r'inventory-item-form\?Key=([a-f0-9-]+)', parts[0].split('<tr')[-1])
        if link_match:
            return link_match.group(1)
            
    return None

def create_item(biz_key, name, code, price):
    # check if exists first
    existing = find_item_uuid(biz_key, name)
    if existing:
        return existing

    url = f"{BASE_URL}/inventory-item-form?{biz_key}"
    field_name = get_form_field_name(url)
    
    data = {
        "Name": name,
        "ItemCode": code,
        "SalesPrice": price,
        "UnitName": "Each"
    }
    
    payload = {field_name: json.dumps(data)}
    resp = SESSION.post(url, data=payload)
    
    # Find the new UUID
    return find_item_uuid(biz_key, name)

def create_invoice(biz_key, customer_name, item_uuid, qty, date="2025-01-15"):
    # Need customer UUID first. 
    # Simplified: We'll assume Alfreds Futterkiste exists (seed data)
    # We need to get the "New Sales Invoice" form to get the field name
    url = f"{BASE_URL}/sales-invoice-form?{biz_key}"
    field_name = get_form_field_name(url)
    
    # We need a Customer UUID. Let's scrape one from the customers list or just create one if needed.
    # We'll use the API to search customers.
    cust_resp = SESSION.get(f"{BASE_URL}/customers?{biz_key}")
    cust_match = re.search(r'customer-form\?Key=([a-f0-9-]+)', cust_resp.text)
    if not cust_match:
        print("Error: No customers found")
        return None
    customer_uuid = cust_match.group(1)
    
    invoice_data = {
        "IssueDate": date,
        "Customer": customer_uuid,
        "Lines": [{
            "Item": item_uuid,
            "Qty": qty,
            "UnitPrice": 20
        }]
    }
    
    payload = {field_name: json.dumps(invoice_data)}
    # Submit
    resp = SESSION.post(url, data=payload)
    
    # Extract the View Link to get the Invoice Key
    # The response is usually a redirect to the view or list
    # We can assume it was the last created.
    # Let's scrape the Sales Invoices list for the top item
    list_resp = SESSION.get(f"{BASE_URL}/sales-invoices?{biz_key}")
    # First view link
    inv_match = re.search(r'sales-invoice-view\?Key=([a-f0-9-]+)', list_resp.text)
    return inv_match.group(1) if inv_match else None

def create_purchase_invoice(biz_key, supplier_name, item_uuid, qty, date="2025-01-16"):
    url = f"{BASE_URL}/purchase-invoice-form?{biz_key}"
    field_name = get_form_field_name(url)
    
    # Find supplier
    sup_resp = SESSION.get(f"{BASE_URL}/suppliers?{biz_key}")
    sup_match = re.search(r'supplier-form\?Key=([a-f0-9-]+)', sup_resp.text)
    if not sup_match:
        print("Error: No suppliers found")
        return None
    supplier_uuid = sup_match.group(1)
    
    invoice_data = {
        "IssueDate": date,
        "Supplier": supplier_uuid,
        "Lines": [{
            "Item": item_uuid,
            "Qty": qty,
            "UnitPrice": 10
        }]
    }
    
    payload = {field_name: json.dumps(invoice_data)}
    SESSION.post(url, data=payload)
    
    list_resp = SESSION.get(f"{BASE_URL}/purchase-invoices?{biz_key}")
    inv_match = re.search(r'purchase-invoice-view\?Key=([a-f0-9-]+)', list_resp.text)
    return inv_match.group(1) if inv_match else None

def main():
    try:
        key = get_business_key()
        if not key:
            print("Error: Could not find business key")
            sys.exit(1)
            
        print(f"Business Key: {key}")
        
        # 1. Ensure Master Item Exists
        master_uuid = create_item(key, "Aniseed Syrup", "COND-001", 10.0)
        
        # 2. Create Duplicate Item
        dup_uuid = create_item(key, "Aniseed Syrup (Old)", "COND-001-OLD", 10.0)
        
        # 3. Create Sales Invoice with Duplicate
        si_key = create_invoice(key, "Alfreds Futterkiste", dup_uuid, 10)
        
        # 4. Create Purchase Invoice with Duplicate
        pi_key = create_purchase_invoice(key, "Exotic Liquids", dup_uuid, 50)
        
        result = {
            "business_key": key,
            "master_item_uuid": master_uuid,
            "duplicate_item_uuid": dup_uuid,
            "sales_invoice_key": si_key,
            "purchase_invoice_key": pi_key
        }
        
        with open("/tmp/task_ids.json", "w") as f:
            json.dump(result, f)
            
        print("Setup successful")
        
    except Exception as e:
        print(f"Setup failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

echo "Running setup script..."
python3 /tmp/setup_inventory_mess.py

# Open Manager at Inventory Items
open_manager_at "inventory"

# Capture initial screenshot
echo "Capturing initial state..."
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="