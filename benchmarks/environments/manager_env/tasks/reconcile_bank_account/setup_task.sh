#!/bin/bash
set -e
echo "=== Setting up reconcile_bank_account task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is running
wait_for_manager 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the python setup script
cat > /tmp/setup_reconciliation_data.py << 'PYEOF'
import requests
import re
import sys
import json

BASE_URL = "http://localhost:8080"
SESSION = requests.Session()

def get_form_token(html):
    # Extract the UUID token used for form submissions
    # Look for name="UUID" value="{}" pattern
    # In Manager, it's often the key of the hidden input
    match = re.search(r'name="([a-f0-9-]{36})"\s+value="\{"', html)
    if match:
        return match.group(1)
    # Fallback search
    match = re.search(r'name="([a-f0-9-]{36})"', html)
    return match.group(1) if match else None

def login():
    SESSION.post(f"{BASE_URL}/login", data={"Username": "administrator"}, allow_redirects=True)

def get_business_key(name="Northwind Traders"):
    resp = SESSION.get(f"{BASE_URL}/businesses")
    # Regex to find link like /start?Key=... for the business name
    # The HTML structure varies, but usually: <a href="start?Key=...">Northwind Traders</a>
    match = re.search(r'start\?([^"&\s]+)[^<]{0,300}' + re.escape(name), resp.text)
    if match:
        return match.group(1)
    
    # Fallback: just get the first key found if specific name search fails (unlikely for Northwind)
    match = re.search(r'start\?([^"&\s]+)', resp.text)
    return match.group(1) if match else None

def enable_bank_reconciliations(biz_key):
    # 1. Get current tabs
    # The tabs form is usually at /tabs-form?Key=...
    # We need to find the link to it from the dashboard or settings
    # Direct URL construction is usually safe in Manager: /tabs-form?Key=...
    
    # We need to submit the form. 
    # The form submission endpoint is the same URL with POST.
    # Payload requires the UUID key and the JSON of enabled tabs.
    
    resp = SESSION.get(f"{BASE_URL}/tabs-form?{biz_key}")
    token = get_form_token(resp.text)
    
    if not token:
        print("Could not find form token for tabs")
        return

    # Construct tabs JSON. We want default + BankReconciliations
    tabs = {
        "BankAndCashAccounts": True,
        "Receipts": True,
        "Payments": True,
        "BankReconciliations": True, # ENABLE THIS
        "Customers": True,
        "SalesInvoices": True,
        "Suppliers": True,
        "PurchaseInvoices": True,
        "InventoryItems": True,
        "JournalEntries": True,
        "Reports": True
    }
    
    data = {
        token: json.dumps(tabs)
    }
    
    # Post
    SESSION.post(f"{BASE_URL}/tabs-form?{biz_key}", data=data)
    print("Enabled Bank Reconciliations module")

def create_petty_cash(biz_key):
    # Create "Petty Cash" account
    resp = SESSION.get(f"{BASE_URL}/bank-or-cash-account-form?{biz_key}")
    token = get_form_token(resp.text)
    
    account_data = {
        "Name": "Petty Cash",
        "Currency": "" # Base currency
    }
    
    # Check if exists first to avoid duplicates? 
    # For simplicity, we assume clean slate or just create another one.
    # Better: check list.
    list_resp = SESSION.get(f"{BASE_URL}/bank-and-cash-accounts?{biz_key}")
    if "Petty Cash" in list_resp.text:
        # Find its ID to use for transactions
        # This is harder to parse without BeautifulSoup, but we'll try regex
        # Pattern: <a href="bank-or-cash-account-form?Key=...&FileID=UUID">Petty Cash</a>
        match = re.search(r'bank-or-cash-account-form\?' + re.escape(biz_key) + r'&amp;FileID=([a-f0-9-]{36})">Petty Cash', list_resp.text)
        if match:
            return match.group(1)
        # Try without entity escape
        match = re.search(r'bank-or-cash-account-form\?' + re.escape(biz_key) + r'&FileID=([a-f0-9-]{36})">Petty Cash', list_resp.text)
        if match:
            return match.group(1)
        return None

    SESSION.post(f"{BASE_URL}/bank-or-cash-account-form?{biz_key}", data={token: json.dumps(account_data)})
    print("Created Petty Cash account")
    
    # Fetch ID of newly created account
    return create_petty_cash(biz_key)

def create_transactions(biz_key, account_id):
    if not account_id:
        print("No account ID for Petty Cash")
        return

    # 1. Receipt: $200 Capital
    # /receipt-form?Key=...
    resp = SESSION.get(f"{BASE_URL}/receipt-form?{biz_key}")
    token = get_form_token(resp.text)
    
    receipt = {
        "Date": "2025-01-01",
        "CreditAccount": account_id, # Bank account is the "CreditAccount" in the form context? 
        # Wait, in Receipt form:
        # "BankAccount": the account receiving money
        # "Lines": allocation
        "BankAccount": account_id,
        "Reference": "REC-001",
        "Description": "Initial Capital",
        "Lines": [
            {
                "Amount": 200.00
                # Account: usually we'd select an equity account, but for this task, 
                # leaving it Suspense or just unallocated is fine as long as the bank balance updates.
                # But let's try to be clean.
            }
        ]
    }
    SESSION.post(f"{BASE_URL}/receipt-form?{biz_key}", data={token: json.dumps(receipt)})
    print("Created Receipt: $200")

    # 2. Payment: $20 Supplies
    resp = SESSION.get(f"{BASE_URL}/payment-form?{biz_key}")
    token = get_form_token(resp.text)
    payment1 = {
        "Date": "2025-01-05",
        "BankAccount": account_id,
        "Reference": "PAY-001",
        "Description": "Office Supplies",
        "Lines": [{"Amount": 20.00}]
    }
    SESSION.post(f"{BASE_URL}/payment-form?{biz_key}", data={token: json.dumps(payment1)})
    print("Created Payment: $20")

    # 3. Payment: $10 Postage
    resp = SESSION.get(f"{BASE_URL}/payment-form?{biz_key}")
    token = get_form_token(resp.text)
    payment2 = {
        "Date": "2025-01-15",
        "BankAccount": account_id,
        "Reference": "PAY-002",
        "Description": "Postage",
        "Lines": [{"Amount": 10.00}]
    }
    SESSION.post(f"{BASE_URL}/payment-form?{biz_key}", data={token: json.dumps(payment2)})
    print("Created Payment: $10")


def main():
    try:
        login()
        biz_key = get_business_key()
        if not biz_key:
            print("Error: Northwind Traders not found")
            sys.exit(1)
            
        print(f"Business Key: {biz_key}")
        
        enable_bank_reconciliations(biz_key)
        account_id = create_petty_cash(biz_key)
        create_transactions(biz_key, account_id)
        
    except Exception as e:
        print(f"Setup failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
PYEOF

# Run the python setup script
python3 /tmp/setup_reconciliation_data.py

# Clean up
rm /tmp/setup_reconciliation_data.py

# Open Manager at Bank Reconciliations page
# Note: Since there are no reconciliations yet, it just shows the list (empty)
# We navigate to 'Bank Reconciliations'
open_manager_at "bank_reconciliations"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="