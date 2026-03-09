#!/bin/bash
set -e
echo "=== Setting up Transfer Inventory Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager.io is running
wait_for_manager 60

# ---------------------------------------------------------------------------
# Configure Initial State: Ensure specific modules are DISABLED
# ---------------------------------------------------------------------------
echo "Configuring Manager.io initial state (disabling target modules)..."

PYTHON_SETUP_SCRIPT=$(cat << 'EOF'
import requests
import re
import sys
import json

MANAGER_URL = "http://localhost:8080"
s = requests.Session()

# Login
s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)

# Get Business Key for Northwind
resp = s.get(f"{MANAGER_URL}/businesses")
m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
if not m:
    print("Northwind Traders not found")
    sys.exit(1)
biz_key = m.group(1)
print(f"Business Key: {biz_key}")

# Get Tabs Form
tabs_url = f"{MANAGER_URL}/tabs-form?{biz_key}"
resp = s.get(tabs_url)
form_token_m = re.search(r'name="([a-f0-9-]+)" value="{}"', resp.text)

if form_token_m:
    token = form_token_m.group(1)
    # Define tabs - EXCLUDING InventoryLocations and InventoryTransfers
    # We keep the basics enabling in setup_data.sh
    tabs_config = {
        "BankAndCashAccounts": True,
        "Receipts": True,
        "Payments": True,
        "Customers": True,
        "SalesInvoices": True,
        "Suppliers": True,
        "PurchaseInvoices": True,
        "InventoryItems": True, # Needed for the task
        "JournalEntries": True,
        "Reports": True,
        # Explicitly False/Missing:
        "InventoryLocations": False,
        "InventoryTransfers": False
    }
    
    # Post update
    post_data = {
        token: json.dumps(tabs_config)
    }
    # We also need to preserve the file header if it exists, but usually just the token field works for JSON blobs
    r = s.post(tabs_url, data=post_data)
    print(f"Tabs configuration updated: {r.status_code}")
else:
    print("Could not find tabs form token")
EOF
)

python3 -c "$PYTHON_SETUP_SCRIPT"

# ---------------------------------------------------------------------------
# Browser Setup
# ---------------------------------------------------------------------------

# Start Firefox at the Summary page
echo "Opening Manager.io..."
open_manager_at "summary"

# Wait for window
wait_for_window "Firefox" 30

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
echo "Capturing initial screenshot..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="