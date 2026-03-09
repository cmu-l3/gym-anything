#!/bin/bash
# Setup script for procure_quote_to_order
# Ensures "Purchase Quotes" module is DISABLED initially.

echo "=== Setting up procure_quote_to_order task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is running
wait_for_manager 60

# Record start time
date +%s > /tmp/task_start_time.txt

# ------------------------------------------------------------------
# Python script to reset Tabs (Disable PurchaseQuotes)
# ------------------------------------------------------------------
python3 -c '
import requests
import re
import sys

URL = "http://localhost:8080"
S = requests.Session()

def get_biz_key(html):
    m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", html)
    if not m: m = re.search(r"start\?([^\"&\s]+)", html)
    return m.group(1) if m else None

try:
    # Login
    S.post(f"{URL}/login", data={"Username": "administrator"}, timeout=10)
    
    # Get Business Key
    resp = S.get(f"{URL}/businesses", timeout=10)
    key = get_biz_key(resp.text)
    if not key:
        print("Error: Could not find business key")
        sys.exit(1)
        
    # Get Tab Form
    resp = S.get(f"{URL}/tabs-form?{key}", timeout=10)
    
    # Extract the hidden field name for the tabs JSON
    # It usually looks like name="[GUID]" value="{...}"
    m = re.search(r"name=\"([a-f0-9-]+)\" value=\"\{", resp.text)
    if m:
        field_name = m.group(1)
        # Define tabs WITHOUT PurchaseQuotes (and also ensure PurchaseOrders is enabled for the target)
        # Default set from setup_data.sh + PurchaseOrders
        tabs_json = "{\"BankAndCashAccounts\":true,\"Receipts\":true,\"Payments\":true,\"Customers\":true,\"SalesInvoices\":true,\"CreditNotes\":true,\"Suppliers\":true,\"PurchaseInvoices\":true,\"DebitNotes\":true,\"InventoryItems\":true,\"JournalEntries\":true,\"Reports\":true,\"PurchaseOrders\":true,\"PurchaseQuotes\":false}"
        
        # Post update
        S.post(f"{URL}/tabs-form?{key}", data={field_name: tabs_json}, timeout=10)
        print("Purchase Quotes module disabled via API.")
    else:
        print("Warning: Could not find Tabs form field. Module state might be inconsistent.")

except Exception as e:
    print(f"Setup Error: {e}")
'

# Open Manager at Summary page
echo "Opening Manager.io..."
open_manager_at "summary"

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="