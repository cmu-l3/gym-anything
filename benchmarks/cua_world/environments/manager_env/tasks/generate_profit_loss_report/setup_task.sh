#!/bin/bash
echo "=== Setting up generate_profit_loss_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Manager is running
wait_for_manager 60

# 2. Record start time
date +%s > /tmp/task_start_time.txt

# 3. Clean up previous output
rm -f /home/ga/Documents/pnl_report.txt
mkdir -p /home/ga/Documents

# 4. Generate Seed Data (Transactions for March 2024)
# We use a python script to interact with the API to ensure precise data
echo "Generating seed transactions..."
python3 -c '
import requests
import sys
import json
import re

MANAGER_URL = "http://localhost:8080"
AUTH = ("administrator", "")

def get_business_key():
    try:
        s = requests.Session()
        s.auth = AUTH
        # Login to get cookies
        s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"})
        
        # Get businesses page
        resp = s.get(f"{MANAGER_URL}/businesses")
        # Find Northwind Traders key
        m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", resp.text)
        if m:
            return m.group(1)
        
        # Fallback to first business if Northwind not explicitly named in link (unlikely with setup script)
        m = re.search(r"start\?([^\"&\s]+)", resp.text)
        return m.group(1) if m else None
    except Exception as e:
        print(f"Error getting business key: {e}")
        return None

def create_transaction(biz_key, endpoint, data):
    # Need to get the form field name (CSRF-like token)
    form_url = f"{MANAGER_URL}/{endpoint}-form?{biz_key}"
    s = requests.Session()
    s.auth = AUTH
    form_page = s.get(form_url).text
    
    # Extract the UUID field name for the JSON payload
    # Pattern: name="[uuid]" value="{}"
    m = re.search(r"name=\"([a-f0-9-]+)\" value=\"\{\}\"", form_page)
    if not m:
        # Fallback search
        m = re.search(r"name=\"([a-f0-9-]+)\"", form_page)
        
    if m:
        field_name = m.group(1)
        payload = {field_name: json.dumps(data)}
        resp = s.post(form_url, data=payload)
        print(f"Created {endpoint}: {resp.status_code}")
        return resp.status_code == 303 or resp.status_code == 200
    return False

key = get_business_key()
if not key:
    print("Could not find business key")
    sys.exit(1)

print(f"Using Business Key: {key}")

# Transaction 1: Sales Invoice - $4,500 (Income)
# Date: 2024-03-15
si1 = {
    "IssueDate": "2024-03-15",
    "Description": "Organic Herbal Tea - 50 cases",
    "Lines": [{
        "Item": {"Name": "Services"}, # simplified
        "Description": "Organic Herbal Tea",
        "Qty": 1,
        "UnitPrice": 4500,
        "Account": "Sales" 
        # Note: Account UUIDs usually required, but text matching often works in import. 
        # However, for robustness, we rely on the default setup_data.sh accounts.
        # If text matching fails, we just send basic lines which usually default to Suspense or Sales.
        # Let us try a generic approach that Manager accepts.
    }]
}
# We will use a simpler payload structure that Manager often accepts for "New" items
# or rely on the fact that setup_data.sh might have created accounts.
# For this task, strict account mapping via API is complex without querying Account UUIDs.
# Alternative: We trust the agent will see whatever is posted.
# We will post to "sales-invoice"
create_transaction(key, "sales-invoice", si1)

# Transaction 2: Sales Invoice - $6,800 (Income)
# Date: 2024-03-22
si2 = {
    "IssueDate": "2024-03-22",
    "Description": "Artisan Olive Oil",
    "Lines": [{"Description": "Artisan Olive Oil", "Qty": 1, "UnitPrice": 6800}]
}
create_transaction(key, "sales-invoice", si2)

# Transaction 3: Purchase Invoice - $3,200 (Expense)
# Date: 2024-03-10
pi1 = {
    "IssueDate": "2024-03-10",
    "Description": "Imported Fruit Syrup",
    "Lines": [{"Description": "Imported Fruit Syrup", "Qty": 1, "UnitPrice": 3200}]
}
create_transaction(key, "purchase-invoice", pi1)

'

# 5. Open Manager to Summary page
open_manager_at "summary"

# 6. Capture initial state
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup complete ==="