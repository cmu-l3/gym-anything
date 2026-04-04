#!/bin/bash
echo "=== Setting up correct_payment_allocation task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is ready
wait_for_manager 60

# Record start time
date +%s > /tmp/task_start_time.txt

# Create the specific transaction scenario using Python
# This script logs in, creates necessary accounts, and the target payment
cat > /tmp/setup_scenario.py << 'EOF'
import requests
import json
import sys
import re
import os

MANAGER_URL = "http://localhost:8080"
COOKIE_FILE = "/tmp/mgr_cookies.txt"

def get_form_token(html):
    m = re.search(r'name="([a-f0-9-]{36})"', html)
    return m.group(1) if m else None

def login():
    s = requests.Session()
    try:
        r = s.get(MANAGER_URL + "/businesses", timeout=10)
        # If redirect to login
        if "login" in r.url:
            s.post(MANAGER_URL + "/login", data={"Username": "administrator"}, timeout=10)
    except Exception as e:
        print(f"Login failed: {e}")
        sys.exit(1)
    return s

def get_business_key(s):
    r = s.get(MANAGER_URL + "/businesses")
    # Find Northwind Traders key
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
    if not m:
        # Fallback to any business if Northwind not found (should be there from env setup)
        m = re.search(r'start\?([^"&\s]+)', r.text)
    return m.group(1) if m else None

def get_or_create_account(s, biz_key, name, type_key="Expense"):
    # Simplified: We assume standard Chart of Accounts or create if missing.
    # In Manager, this is complex via scraping, so we will try to map common names.
    # For this task, we need UUIDs for "Office Supplies" and "Repairs and Maintenance".
    
    # 1. Get Chart of Accounts (or P&L items)
    # This is tricky without a public API. We will use a hack:
    # We will fetch the "Payment" form, which contains the account dropdown data.
    
    dummy_payment_url = f"{MANAGER_URL}/payment-form?{biz_key}"
    r = s.get(dummy_payment_url)
    
    # Extract options from the select list for Accounts
    # This regex looks for the options in the account select dropdown
    # We look for the text and capture the value (UUID)
    
    # Regex for "Office Supplies"
    # <option value="UUID">Office Supplies</option>
    m_supplies = re.search(r'<option value="([^"]+)">.*?Office Supplies.*?</option>', r.text, re.IGNORECASE)
    uuid_supplies = m_supplies.group(1) if m_supplies else None
    
    # Regex for "Repairs and Maintenance"
    m_repairs = re.search(r'<option value="([^"]+)">.*?Repairs and Maintenance.*?</option>', r.text, re.IGNORECASE)
    uuid_repairs = m_repairs.group(1) if m_repairs else None
    
    # Get Bank Account UUID (Cash on Hand)
    m_bank = re.search(r'<option value="([^"]+)">.*?Cash on Hand.*?</option>', r.text, re.IGNORECASE)
    uuid_bank = m_bank.group(1) if m_bank else None
    
    return uuid_supplies, uuid_repairs, uuid_bank, get_form_token(r.text)

def create_payment(s, biz_key, bank_uuid, account_uuid, form_token):
    url = f"{MANAGER_URL}/payment-form?{biz_key}"
    
    # Construct form data
    # Manager.io forms use a unique UUID field name for the JSON blob
    # Structure: {token: json_string}
    
    payment_data = {
        "Date": "2025-05-15",
        "Description": "Payment to TechFix Services",
        "Payee": "TechFix Services",
        "CreditAccount": bank_uuid, # Bank account paying FROM
        "Lines": [
            {
                "Account": account_uuid, # Paying FOR (Expense)
                "Amount": 600.00
            }
        ]
    }
    
    data = {
        form_token: json.dumps(payment_data)
    }
    
    r = s.post(url, data=data)
    
    # Extract the UUID of the created payment from the redirect URL or response
    # Usually redirects to /payments?{biz_key}
    # We need to find the specific payment we just made to store its ID.
    
    # Fetch payments list
    r_list = s.get(f"{MANAGER_URL}/payments?{biz_key}")
    
    # Find the link to the payment with our unique details
    # href="payment-view?Key=UUID&..."
    # Search for TechFix and date
    # Row contains "15/05/2025", "TechFix Services", "600.00"
    
    # Regex to find the UUID associated with this row
    # HTML structure: <tr ... onclick="window.location.href='payment-view?Key=UUID...'"> ... TechFix ... </tr>
    # or <td ...><a href="payment-view?Key=UUID...">...</a></td>
    
    # We look for the UUID near "TechFix Services"
    pattern = r'Key=([a-f0-9-]{36})[^>]*>.*?TechFix Services'
    m = re.search(pattern, r_list.text, re.DOTALL)
    
    if not m:
        # Try broader search if layout differs
        pattern = r'Key=([a-f0-9-]{36}).{0,500}TechFix Services'
        m = re.search(pattern, r_list.text, re.DOTALL)
        
    payment_uuid = m.group(1) if m else None
    return payment_uuid

def main():
    s = login()
    biz_key = get_business_key(s)
    if not biz_key:
        print("Error: Northwind business not found")
        sys.exit(1)
        
    u_supplies, u_repairs, u_bank, form_token = get_or_create_account(s, biz_key, None)
    
    if not u_supplies:
        print("Error: Office Supplies account not found")
        # In a real robust script, we would create it. 
        # For Northwind, it should exist. If not, fail setup.
        sys.exit(1)
        
    if not u_repairs:
        print("Error: Repairs and Maintenance account not found")
        # Same here.
        sys.exit(1)
        
    if not u_bank:
        print("Error: Cash on Hand account not found")
        sys.exit(1)
        
    # Create the payment
    pid = create_payment(s, biz_key, u_bank, u_supplies, form_token)
    
    if not pid:
        print("Error: Failed to create payment or retrieve ID")
        sys.exit(1)
        
    # Save metadata
    meta = {
        "business_key": biz_key,
        "payment_uuid": pid,
        "accounts": {
            "office_supplies": u_supplies,
            "repairs": u_repairs,
            "bank": u_bank
        }
    }
    
    with open("/tmp/task_metadata.json", "w") as f:
        json.dump(meta, f, indent=2)
        
    print(f"Setup successful. Payment {pid} created.")

if __name__ == "__main__":
    main()
EOF

# Run the python setup
python3 /tmp/setup_scenario.py

# Launch Firefox directly to Payments tab
open_manager_at "payments"

# Maximize and screenshot
sleep 5
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="