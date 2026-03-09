#!/bin/bash
echo "=== Setting up record_customer_refund task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager.io is running
wait_for_manager 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# Capture initial payment count for verification (to ensure a NEW one is created)
# We use a python script to scrape the current count via requests
python3 -c '
import requests, re, sys

MANAGER_URL = "http://localhost:8080"
s = requests.Session()

# Login
s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)

# Get Business Key
biz_page = s.get(f"{MANAGER_URL}/businesses").text
m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_page)
if not m:
    m = re.search(r"start\?([^\"&\s]+)", biz_page)
    
if m:
    biz_key = m.group(1)
    # Get Payments list
    resp = s.get(f"{MANAGER_URL}/payments?{biz_key}")
    # Count rows in the table body (rough estimate)
    count = resp.text.count("View?Key=") 
    print(count)
else:
    print("0")
' > /tmp/initial_payment_count.txt

echo "Initial payment count: $(cat /tmp/initial_payment_count.txt)"

# Open Firefox at the Payments module
# We pass "payments" to the helper, but NOT "new", so the agent has to click "New Payment"
# This tests their ability to find the button and navigate the form from scratch.
echo "Opening Manager.io at Payments list..."
open_manager_at "payments"

echo "=== Task setup complete ==="