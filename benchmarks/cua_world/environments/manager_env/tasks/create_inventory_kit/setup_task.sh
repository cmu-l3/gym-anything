#!/bin/bash
echo "=== Setting up create_inventory_kit task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is running
wait_for_manager 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------------------
# Setup Data via Python Script (Create Items, Ensure Kit Module Disabled)
# ---------------------------------------------------------------------------
echo "Configuring Northwind Traders data..."

python3 -c '
import requests
import sys
import json
import re

MANAGER_URL = "http://localhost:8080"
SESSION = requests.Session()

def login():
    SESSION.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)

def get_business_key(name="Northwind Traders"):
    resp = SESSION.get(f"{MANAGER_URL}/businesses")
    # Regex to find the key for Northwind Traders
    # Link format: <a href="start?Key=...">Northwind Traders</a>
    m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}" + re.escape(name), resp.text)
    if m:
        return m.group(1)
    # Fallback to any key if not found (though setup_manager should have created it)
    m = re.search(r"start\?([^\"&\s]+)", resp.text)
    return m.group(1) if m else None

def get_form_token(url):
    resp = SESSION.get(url)
    # Find hidden input: <input type="hidden" name="..." value="{}" />
    # The name is a UUID
    m = re.search(r"name=\"([a-f0-9\-]+)\" value=\"\{\}\"", resp.text)
    return m.group(1) if m else None

def create_item(biz_key, name, code, sales_price, purchase_price):
    # Check if item exists first to avoid duplicates
    list_url = f"{MANAGER_URL}/inventory-items?{biz_key}"
    resp = SESSION.get(list_url)
    if name in resp.text:
        print(f"Item {name} already exists.")
        return

    # Get New Item form to get token
    form_url = f"{MANAGER_URL}/inventory-item-form?{biz_key}"
    token = get_form_token(form_url)
    if not token:
        print(f"Could not get token for {name}")
        return

    data = {
        "ItemName": name,
        "ItemCode": code,
        "SalesPrice": sales_price,
        "PurchasePrice": purchase_price,
        "UnitName": "Unit"
    }
    
    # Manager expects the JSON in the field named by the token
    post_data = {token: json.dumps(data)}
    r = SESSION.post(form_url, data=post_data)
    print(f"Created item {name}: {r.status_code}")

def configure_tabs(biz_key):
    # Ensure Inventory Kits is DISABLED
    # We enable standard tabs but explicitly exclude InventoryKits
    tabs_url = f"{MANAGER_URL}/tabs-form?{biz_key}"
    token = get_form_token(tabs_url)
    if not token: 
        return
        
    # Standard Northwind tabs minus InventoryKits
    tabs_config = {
        "BankAndCashAccounts": True,
        "Receipts": True,
        "Payments": True,
        "Customers": True,
        "SalesInvoices": True,
        "Suppliers": True,
        "PurchaseInvoices": True,
        "InventoryItems": True,
        "Reports": True
        # "InventoryKits": False  <-- Implicitly false if omitted/false
    }
    
    post_data = {token: json.dumps(tabs_config)}
    SESSION.post(tabs_url, data=post_data)
    print("Tabs configured (Inventory Kits disabled)")

try:
    login()
    key = get_business_key()
    if not key:
        print("Error: Northwind Traders business not found")
        sys.exit(1)
        
    print(f"Business Key: {key}")
    
    # 1. Configure tabs (hide inventory kits)
    configure_tabs(key)
    
    # 2. Create required inventory items
    create_item(key, "Chai Tea", "CHAI", 12.00, 8.00)
    create_item(key, "Extra Virgin Olive Oil", "OIL", 18.50, 11.00)
    create_item(key, "Dark Chocolate Assortment", "CHOC", 15.00, 9.50)
    
except Exception as e:
    print(f"Setup failed: {e}")
    sys.exit(1)
'

# ---------------------------------------------------------------------------
# Prepare Browser
# ---------------------------------------------------------------------------

# Record initial count of inventory kits (should be 0 or inaccessible)
# We can just write 0 as we disabled the tab
echo "0" > /tmp/initial_kit_count.txt

# Open Firefox at Summary page
echo "Opening Manager.io..."
open_manager_at "summary"

# Capture initial screenshot
sleep 5
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="