#!/bin/bash
echo "=== Setting up Record Payment with Withholding task ==="

source /workspace/scripts/task_utils.sh

# Wait for Manager to be ready
wait_for_manager 60

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

COOKIE_FILE="/tmp/mgr_cookies.txt"
MANAGER_URL="http://localhost:8080"

# 1. Login
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# 2. Get Business Key (Northwind Traders)
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(echo "$BIZ_PAGE" | grep -oP 'start\?\K[^"]+(?=">Northwind Traders)' | head -1)

if [ -z "$BIZ_KEY" ]; then
    # Fallback if specific name not found, grab the first one
    BIZ_KEY=$(echo "$BIZ_PAGE" | grep -oP 'start\?\K[^"]+' | head -1)
fi
echo "$BIZ_KEY" > /tmp/biz_key.txt
echo "Business Key: $BIZ_KEY"

# 3. Create 'Withholding Tax Receivable' Account
# We need to find the UUID for "Assets" group or just create it as a top level account if possible.
# For simplicity in automation, we'll try to post to balance-sheet-account-form.
# First, get the form token/structure by GET request (simplified here, assuming standard fields)
# Note: Creating structural elements via curl blindly is hard due to UUIDs.
# ALTERNATIVE: We use Python to interact more robustly or just create the Invoice.
# The task description says "An asset account ... exists". We MUST create it.

python3 - <<PYEOF
import requests
import re
import sys

s = requests.Session()
url = "$MANAGER_URL"
biz_key = "$BIZ_KEY"
cookies = {"manager-cookies": "true"} # Placeholder if needed, strictly using jar below

# Login logic handled by curl cookies passed via file? Python requests is easier standalone.
s.post(f"{url}/login", data={"Username": "administrator"})

# Create Account
# 1. Get New Account Form to find hidden input (FileID/UUID)
r = s.get(f"{url}/balance-sheet-account-form?{biz_key}")
form_token = re.search(r'name="([a-f0-9-]+)" value="{}"', r.text)
if form_token:
    token_name = form_token.group(1)
    # Group: Assets
    payload = {
        token_name: '{"Name":"Withholding Tax Receivable","Group":"Assets","Kind":"Asset"}'
    }
    s.post(f"{url}/balance-sheet-account-form?{biz_key}", data=payload)
    print("Created 'Withholding Tax Receivable' account")

# Create Invoice #INV-CONS-001
# 1. Find Customer UUID for Alfreds
r = s.get(f"{url}/customers?{biz_key}")
cust_match = re.search(r'customer-view\?Key=([^&]+)&[^"]+">Alfreds', r.text)
if cust_match:
    cust_key = cust_match.group(1)
    
    # 2. Get Sales Invoice Form
    r = s.get(f"{url}/sales-invoice-form?{biz_key}")
    form_token_match = re.search(r'name="([a-f0-9-]+)" value="{}"', r.text)
    if form_token_match:
        token_name = form_token_match.group(1)
        # JSON payload for invoice
        inv_json = {
            "IssueDate": "2025-03-01",
            "Reference": "INV-CONS-001",
            "Customer": cust_key,
            "Description": "Consulting Services",
            "Lines": [{
                "Description": "Consulting Hours",
                "Qty": 1,
                "UnitPrice": 1000
            }]
        }
        import json
        payload = {token_name: json.dumps(inv_json)}
        s.post(f"{url}/sales-invoice-form?{biz_key}", data=payload)
        print("Created Invoice #INV-CONS-001")
    else:
        print("Error: Could not find form token for invoice")
else:
    print("Error: Could not find Alfreds Futterkiste")

PYEOF

# 4. Record Initial Balances (Cash on Hand)
CASH_BALANCE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/summary?$BIZ_KEY" | grep -A 5 "Cash on Hand" | grep -oP '[0-9,]+\.[0-9]{2}' | head -1 | tr -d ',' || echo "0.00")
echo "$CASH_BALANCE" > /tmp/initial_cash.txt

# 5. Open Browser to Receipts tab
open_manager_at "receipts" "new"

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="