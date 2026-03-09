#!/bin/bash
echo "=== Setting up add_bank_account task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager.io is running
wait_for_manager 60

# Record initial count of bank accounts
# We use a small python script to query the API/Page
echo "Recording initial bank account count..."
python3 -c "
import requests, re
s = requests.Session()
url = 'http://localhost:8080'
# Login
s.post(f'{url}/login', data={'Username': 'administrator'})
# Get Business Key for Northwind
resp = s.get(f'{url}/businesses')
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
if m:
    biz_key = m.group(1)
    # Get Bank Accounts page
    resp = s.get(f'{url}/bank-and-cash-accounts?{biz_key}')
    # Count rows in the table (simple heuristic: count 'Edit' buttons or row classes)
    count = resp.text.count('ret=') # 'ret=' is usually in the Edit link
    print(count)
else:
    print('0')
" > /tmp/initial_count.txt

echo "Initial count: $(cat /tmp/initial_count.txt)"

# Open Firefox at the Bank Accounts module
# We don't click 'New' automatically, let the agent find it
open_manager_at "bank_accounts"

# Take initial screenshot
echo "Capturing initial state..."
sleep 5 # Wait for Firefox to load
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="