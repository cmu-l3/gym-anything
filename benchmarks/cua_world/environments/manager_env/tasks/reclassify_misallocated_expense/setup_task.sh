#!/bin/bash
# Setup for reclassify_misallocated_expense
# Injects a misclassified payment into Manager.io

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Reclassify Expense Task ==="

# 1. Ensure Manager is running
wait_for_manager 60

# 2. Python script to inject specific data (Accounts & Payments)
#    We use Python for better handling of UUIDs and form tokens
cat > /tmp/inject_data.py << 'EOF'
import requests
import re
import sys
import json

BASE_URL = "http://localhost:8080"
SESSION = requests.Session()

def get_business_id():
    # Login
    SESSION.post(f"{BASE_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    
    # Find Northwind
    resp = SESSION.get(f"{BASE_URL}/businesses")
    # Regex to find the key for Northwind Traders
    # Link looks like <a href="start?FileID=...">Northwind Traders</a>
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
    if m:
        return m.group(1)
    
    # Fallback to creating it if missing (unlikely given base setup)
    print("Northwind not found, creating...")
    resp = SESSION.post(f"{BASE_URL}/create-new-business", data={"Name": "Northwind Traders"})
    return get_business_id() # recursive retry

def get_form_token(url):
    resp = SESSION.get(url)
    # Extract the hidden input that usually holds the UUID/FileID for the form context
    # Usually <input type="hidden" name="FileID" value="..."> or similar unique ID
    # Manager often uses the URL query param as the ID for existing items, 
    # but for new items, we scrape the form.
    # Actually, Manager forms often post to a URL with a FileID.
    # Let's try to parse the 'name' attribute of the main data payload which is a UUID.
    m = re.search(r'name="([a-f0-9-]{36})"', resp.text)
    if m:
        return m.group(1)
    return None

def create_expense_account(biz_id, name):
    # Check if exists first
    resp = SESSION.get(f"{BASE_URL}/chart-of-accounts?{biz_id}")
    if name in resp.text:
        # Extract UUID if possible, but for setup we might just need to know it exists
        # To get UUID we'd need to parse the Edit link
        m = re.search(r'account-form\?([^"]+)">Edit</a>[^<]*</td>[^<]*<td>' + re.escape(name), resp.text)
        if m:
            print(f"Account '{name}' already exists.")
            return m.group(1) # This is the query string usually containing FileID
    
    # Create
    print(f"Creating account '{name}'...")
    # Get the "New Account" form to find the correct field name
    form_url = f"{BASE_URL}/account-form?{biz_id}&Type=Expense"
    field_name = get_form_token(form_url)
    if not field_name:
        print("Failed to get form token for account")
        return None
        
    data = {
        "Name": name,
        "Type": "Expense"
    }
    # Wrap in the UUID field name
    payload = {field_name: json.dumps(data)}
    resp = SESSION.post(form_url, data=payload)
    
    # Find the new UUID from the redirect or by searching list again
    return create_expense_account(biz_id, name)

def create_payment(biz_id, date, payee, description, amount, account_uuid):
    print(f"Creating payment to '{payee}'...")
    
    # 1. Enable Payments tab if needed (skipping complexity, assuming enabled by default setup)
    
    # 2. Get Payment Form
    form_url = f"{BASE_URL}/payment-form?{biz_id}"
    field_name = get_form_token(form_url)
    
    # Construct the complex JSON object Manager expects
    # Manager stores transaction lines in a 'Lines' array
    payment_data = {
        "Date": date,
        "Payee": payee,
        "Description": description,
        "Lines": [
            {
                "Account": account_uuid,
                "Amount": amount
            }
        ],
        "Reference": "AUTO"
    }
    
    payload = {field_name: json.dumps(payment_data)}
    SESSION.post(form_url, data=payload)

def main():
    try:
        biz_id = get_business_id()
        print(f"Business ID: {biz_id}")
        
        # Access business to set session context
        SESSION.get(f"{BASE_URL}/start?{biz_id}")
        
        # 1. Ensure 'Office Supplies' exists
        os_uuid_query = create_expense_account(biz_id, "Office Supplies")
        # Extract just the UUID if it came back as a query string (e.g. "Key=...")
        # Usually Manager keys are just UUIDs in newer versions, or FileID params.
        # Let's clean it up.
        os_uuid = os_uuid_query.split('=')[-1] if '=' in os_uuid_query else os_uuid_query
        
        print(f"Office Supplies UUID: {os_uuid}")
        
        # 2. Create the target misclassified payment
        # City Grill -> Office Supplies
        create_payment(biz_id, "2025-05-15", "City Grill", "Staff Lunch", 245.00, os_uuid)
        
        # 3. Create some noise
        # Staples -> Office Supplies
        create_payment(biz_id, "2025-05-10", "Staples", "Printer Paper", 49.99, os_uuid)
        
        print("Data injection complete.")
        
    except Exception as e:
        print(f"Error injecting data: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

# Execute injection
python3 /tmp/inject_data.py

# 3. Start Task
echo "$(date +%s)" > /tmp/task_start_time

# Open Browser to Summary
open_manager_at "summary"

# Screenshot initial state
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="