#!/bin/bash
set -e
echo "=== Setting up enable_and_create_purchase_order task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager.io is running
wait_for_manager 60

# -----------------------------------------------------------------------
# CONFIGURE INITIAL STATE: Ensure Purchase Orders is DISABLED
# -----------------------------------------------------------------------
echo "Configuring Manager.io initial state (disabling Purchase Orders)..."

python3 -c '
import requests, re, sys, json

MANAGER_URL = "http://localhost:8080"
s = requests.Session()

# Login
s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)

# Get Business Key
biz_page = s.get(f"{MANAGER_URL}/businesses").text
m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_page)
if not m:
    # Fallback to first business if Northwind specific search fails
    m = re.search(r"start\?([^\"&\s]+)", biz_page)
    
if not m:
    print("Error: Could not find business key")
    sys.exit(1)

biz_key = m.group(1)
print(f"Business Key: {biz_key}")

# Get Tabs Form to disable Purchase Orders
# We need to find the form URL and the hidden UUID field
tabs_page = s.get(f"{MANAGER_URL}/tabs-form?{biz_key}").text

# Extract form action URL
action_m = re.search(r"action=\"([^\"]+)\"", tabs_page)
if not action_m:
    print("Error: Could not find tabs form action")
    sys.exit(1)
action_url = action_m.group(1)

# Extract the main object field name (UUID)
# It usually looks like name="[UUID]" value="{...}"
field_m = re.search(r"name=\"([a-f0-9\-]+)\" value=\"{", tabs_page)
if not field_m:
    print("Error: Could not find tabs form field")
    sys.exit(1)
field_name = field_m.group(1)

# Define enabled tabs (EXCLUDING PurchaseOrders)
# This matches the standard setup_data.sh but ensures PurchaseOrders is False
tabs_config = {
    "BankAndCashAccounts": True,
    "Receipts": True,
    "Payments": True,
    "Customers": True,
    "SalesInvoices": True,
    "CreditNotes": True,
    "Suppliers": True,
    "PurchaseInvoices": True,
    "DebitNotes": True,
    "InventoryItems": True,
    "JournalEntries": True,
    "Reports": True,
    "PurchaseOrders": False  # Explicitly disabled
}

# Post the update
payload = {
    field_name: json.dumps(tabs_config)
}
resp = s.post(f"{MANAGER_URL}{action_url}", data=payload)
print(f"Update Tabs Status: {resp.status_code}")
'

# -----------------------------------------------------------------------
# OPEN BROWSER
# -----------------------------------------------------------------------
echo "Opening Firefox at Dashboard..."

# Open at the summary/dashboard page (not a specific module)
open_manager_at "summary"

# Wait for Firefox to be ready and window to appear
wait_for_window "Firefox" 30

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="