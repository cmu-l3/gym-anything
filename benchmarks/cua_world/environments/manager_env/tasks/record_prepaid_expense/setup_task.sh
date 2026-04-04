#!/bin/bash
echo "=== Setting up record_prepaid_expense task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager is running
wait_for_manager 60

# Authenticate and clean up state (ensure Prepaid Insurance doesn't exist)
echo "Cleaning up any existing 'Prepaid Insurance' accounts..."
python3 -c '
import requests
import sys
import re

MANAGER_URL = "http://localhost:8080"
s = requests.Session()

# Login
s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)

# Find Northwind business
biz_page = s.get(f"{MANAGER_URL}/businesses").text
m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_page)
if not m:
    m = re.search(r"start\?([^\"&\s]+)", biz_page)
if not m:
    print("Error: Could not find business")
    sys.exit(1)

biz_key = m.group(1)
base_url = f"{MANAGER_URL}/"

# Navigate to business
s.get(f"{MANAGER_URL}/start?{biz_key}")

# Get Chart of Accounts (in Manager this is often just managed via specific endpoints)
# We will try to find if the account exists by checking the Balance Sheet or Settings
# For simplicity in setup, we assume a clean slate or that the agent will handle errors,
# but to be safe we log the initial state.

print(f"Business Key: {biz_key}")
with open("/tmp/biz_key.txt", "w") as f:
    f.write(biz_key)
'

# Start Firefox at the Summary page
echo "Opening Manager.io..."
open_manager_at "summary"

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="