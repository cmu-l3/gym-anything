#!/bin/bash
echo "=== Setting up add_expense_accounts task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Manager is running
wait_for_manager 60

# Record initial state of Chart of Accounts (to detect "do nothing")
# We use a small python script to grab the current account list
cat << 'EOF' > /tmp/record_initial_state.py
import requests
import re
import json

BASE_URL = "http://localhost:8080"
SESSION = requests.Session()

def get_business_key():
    # Login
    SESSION.post(f"{BASE_URL}/login", data={"Username": "administrator"})
    # Get businesses page
    resp = SESSION.get(f"{BASE_URL}/businesses")
    # Find Northwind
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', resp.text)
    return m.group(1) if m else None

def get_accounts(key):
    # Navigate to Chart of Accounts
    # First get Settings page to find the link (URL structure varies by version)
    # But usually it's /chart-of-accounts?Key=...
    resp = SESSION.get(f"{BASE_URL}/chart-of-accounts?{key}")
    if resp.status_code != 200:
        return []
    
    # Simple regex to find account names (robust enough for baseline)
    # Looks for text inside table cells
    return re.findall(r'<td[^>]*>([^<]+)</td>', resp.text)

try:
    key = get_business_key()
    if key:
        accounts = get_accounts(key)
        with open("/tmp/initial_accounts.json", "w") as f:
            json.dump(accounts, f)
        print(f"Recorded {len(accounts)} initial accounts")
    else:
        print("Could not find business key")
except Exception as e:
    print(f"Error recording initial state: {e}")
EOF

python3 /tmp/record_initial_state.py

# Open Manager at the Summary page (standard starting point)
echo "Opening Manager.io at Summary..."
open_manager_at "summary"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="