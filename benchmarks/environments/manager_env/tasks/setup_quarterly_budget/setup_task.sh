#!/bin/bash
echo "=== Setting up setup_quarterly_budget task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager is running
wait_for_manager 60

# -----------------------------------------------------------------------
# Configure Initial State: Ensure 'Budgets' module is DISABLED
# -----------------------------------------------------------------------
echo "Configuring Manager.io state (disabling Budgets module)..."

python3 -c '
import requests
import re
import sys

BASE_URL = "http://localhost:8080"
s = requests.Session()

# Login
s.post(f"{BASE_URL}/login", data={"Username": "administrator"}, allow_redirects=True)

# Get Business Key
biz_page = s.get(f"{BASE_URL}/businesses").text
m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_page)
if not m:
    print("Could not find Northwind Traders")
    sys.exit(1)
biz_key = m.group(1)
print(f"Business Key: {biz_key}")

# Go to tabs form to get current state and form tokens
tabs_url = f"{BASE_URL}/tabs-form?{biz_key}"
resp = s.get(tabs_url)
html = resp.text

# Extract the unique file/token ID for the form
# It looks like name="[UUID]" value="{...}"
token_match = re.search(r"name=\"([a-f0-9\-]+)\" value=\"{", html)
if not token_match:
    # Fallback: sometimes the UUID is different or structure varies, try generic
    token_match = re.search(r"name=\"([a-f0-9\-]{36})\"", html)

if token_match:
    token = token_match.group(1)
    # Define tabs WITHOUT Budgets
    # Common tabs: BankAndCashAccounts, Receipts, Payments, Customers, SalesInvoices, etc.
    # We intentionally omit "Budgets"
    tabs_json = "{\"Summary\":true,\"BankAndCashAccounts\":true,\"Receipts\":true,\"Payments\":true,\"Customers\":true,\"SalesInvoices\":true,\"Suppliers\":true,\"PurchaseInvoices\":true,\"InventoryItems\":true,\"Reports\":true,\"Settings\":true}"
    
    # Post the update
    post_resp = s.post(tabs_url, data={token: tabs_json})
    print(f"Disabled Budgets module: {post_resp.status_code}")
else:
    print("Could not find form token to update tabs")
'

# -----------------------------------------------------------------------
# Start Firefox at Summary Page
# -----------------------------------------------------------------------
echo "Opening Manager.io..."
open_manager_at "summary"

# Take initial screenshot
echo "Capturing initial state..."
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="