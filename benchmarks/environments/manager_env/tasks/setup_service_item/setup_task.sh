#!/bin/bash
echo "=== Setting up setup_service_item task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager is running
wait_for_manager 60

# We need to ensure the starting state is clean:
# 1. "Consulting Revenue" account should NOT exist.
# 2. "Non-inventory Items" module should be DISABLED.

echo "Configuring initial state..."

# Python script to clean up environment if needed and ensure module is disabled
python3 - <<'EOF'
import requests
import re
import sys

MANAGER_URL = "http://localhost:8080"
COOKIE_FILE = "/tmp/mgr_setup_cookies.txt"

def get_biz_key(session):
    try:
        r = session.get(f"{MANAGER_URL}/businesses")
        m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
        if not m:
            m = re.search(r'start\?([^"&\s]+)', r.text)
        return m.group(1) if m else None
    except:
        return None

def disable_module(session, biz_key, module_name="NonInventoryItems"):
    # First get the tabs form
    tabs_url = f"{MANAGER_URL}/tabs-form?{biz_key}"
    r = session.get(tabs_url)
    
    # Extract form data
    field_match = re.search(r'name="([^"]+)" value="{}"', r.text)
    if not field_match:
        # Maybe it has values
        field_match = re.search(r'name="([^"]+)" value="([^"]*)"', r.text)
    
    if field_match:
        field_name = field_match.group(1)
        # We need to construct the JSON for enabled tabs.
        # We'll enable standard ones but EXCLUDE NonInventoryItems
        tabs_json = '{"BankAndCashAccounts":true,"Receipts":true,"Payments":true,"Customers":true,"SalesInvoices":true,"CreditNotes":true,"Suppliers":true,"PurchaseInvoices":true,"DebitNotes":true,"InventoryItems":true,"JournalEntries":true,"Reports":true}'
        
        # Post update
        data = {field_name: tabs_json}
        r = session.post(tabs_url, data=data)
        print(f"Tabs updated. {module_name} should be disabled. Status: {r.status_code}")

def main():
    s = requests.Session()
    # Login
    s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"})
    
    biz_key = get_biz_key(s)
    if not biz_key:
        print("Could not find Northwind Traders business")
        sys.exit(1)
        
    print(f"Business Key: {biz_key}")
    
    # Navigate to business to set session context
    s.get(f"{MANAGER_URL}/start?{biz_key}")
    
    # Disable Non-Inventory Items module to ensure clean start
    disable_module(s, biz_key)

if __name__ == "__main__":
    main()
EOF

# Open Manager.io at the Summary page
echo "Opening Manager.io..."
open_manager_at "summary"

# Take initial screenshot
sleep 5
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="