#!/bin/bash
set -e

echo "=== Setting up Enforce Credit Limit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Manager is running and accessible
ensure_manager_running

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create a Python script to inject the specific scenario data
# We use direct API calls for speed and reliability during setup
cat > /tmp/setup_scenario.py << 'EOF'
import requests
import re
import sys
import datetime
import json
import time

MANAGER_URL = "http://localhost:8080"
SESSION = requests.Session()

def get_form_token(url):
    try:
        r = SESSION.get(url, timeout=10)
        # Find the unique field name (UUID) or use fallback
        match = re.search(r'name="([a-f0-9-]{36})"', r.text)
        if match:
            return match.group(1)
        # Fallback for some forms
        match = re.search(r'name="([^"]{30,})"', r.text)
        if match:
            return match.group(1)
    except Exception as e:
        print(f"Error getting token from {url}: {e}")
    return None

def login():
    print("Logging in...")
    SESSION.post(f"{MANAGER_URL}/login", data={"Username": "administrator"})

def get_business_key():
    print("Getting business key...")
    r = SESSION.get(f"{MANAGER_URL}/businesses")
    # Find Northwind Traders key
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', r.text)
    return m.group(1) if m else None

def ensure_customer(biz_key, name):
    print(f"Ensuring customer: {name}")
    # Check if exists (naive check)
    r = SESSION.get(f"{MANAGER_URL}/customers?{biz_key}")
    
    # Extract key if exists
    # Pattern: <td data-label="Name">Name</td>...<a href="customer-form?Key=KEY">
    # Note: The HTML structure varies, robust regex needed
    if name in r.text:
        # Try to find the key associated with this name
        # We split by lines to be safer
        lines = r.text.split('\n')
        curr_key = None
        for line in lines:
            m_key = re.search(r'customer-form\?Key=([a-f0-9-]+)', line)
            if m_key:
                curr_key = m_key.group(1)
            if name in line and curr_key:
                return curr_key
    
    # Create if not found
    token = get_form_token(f"{MANAGER_URL}/customer-form?{biz_key}")
    if not token:
        print("Could not get form token for customer")
        return None
        
    payload_json = json.dumps({"Name": name})
    data = {token: payload_json}
    
    # Submit
    r = SESSION.post(f"{MANAGER_URL}/customer-form?{biz_key}", data=data)
    
    # Get the key now
    return ensure_customer(biz_key, name)

def create_invoice(biz_key, customer_key, amount, days_ago):
    print(f"Creating invoice: {amount} dated {days_ago} days ago")
    date_str = (datetime.date.today() - datetime.timedelta(days=days_ago)).strftime("%Y-%m-%d")
    
    token = get_form_token(f"{MANAGER_URL}/sales-invoice-form?{biz_key}")
    if not token:
        print("Could not get form token for invoice")
        return

    # Payload
    # Note: Manager expects specific JSON structure
    # We use a generic Item or just Description line
    payload_json = json.dumps({
        "IssueDate": date_str,
        "Customer": customer_key,
        "Lines": [{
            "Description": "Wholesale Order",
            "Amount": amount
        }]
    })
    
    data = {token: payload_json}
    SESSION.post(f"{MANAGER_URL}/sales-invoice-form?{biz_key}", data=data)

def main():
    login()
    biz_key = get_business_key()
    if not biz_key:
        print("Northwind Traders business not found!")
        sys.exit(1)
    
    # 1. Save-a-Lot Markets: High balance ($12k), but CURRENT (5 days ago)
    # Should NOT be flagged
    c1 = ensure_customer(biz_key, "Save-a-Lot Markets")
    create_invoice(biz_key, c1, 12000, 5)
    
    # 2. Stop-N-Shop: High balance ($5k), OLD (>90 days ago)
    # THIS IS THE TARGET
    c2 = ensure_customer(biz_key, "Stop-N-Shop")
    create_invoice(biz_key, c2, 5000, 120)
    
    # 3. Quick-Stop Groceries: Low balance ($500), OLD (>90 days ago)
    # Should NOT be flagged (balance too low to be the priority)
    c3 = ensure_customer(biz_key, "Quick-Stop Groceries")
    create_invoice(biz_key, c3, 500, 120)
    
    print("Scenario data setup complete.")

if __name__ == "__main__":
    main()
EOF

# Run the data injection
python3 /tmp/setup_scenario.py

# Open Manager in Firefox at the Reports page to help the agent start
# We'll use the navigate_manager.py util to ensure clean start
echo "Opening Manager.io at Reports module..."
open_manager_at "reports"

# Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="