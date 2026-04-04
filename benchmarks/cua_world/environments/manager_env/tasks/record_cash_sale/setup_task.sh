#!/bin/bash
# Setup script for record_cash_sale task

set -e
echo "=== Setting up record_cash_sale task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Manager is running and accessible
wait_for_manager 60

# 2. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Open Manager to the Receipts module
# We open the list view so the agent has to find "New Receipt"
echo "Opening Manager.io at Receipts module..."
open_manager_at "receipts"

# 4. Record initial state (Receipt count)
# We use a python script to query the API/HTML to get the count of receipts
cat << 'EOF' > /tmp/get_initial_count.py
import requests
import re
import sys

MANAGER_URL = "http://localhost:8080"
try:
    s = requests.Session()
    # Login
    s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    
    # Get Business Key
    biz_page = s.get(f"{MANAGER_URL}/businesses").text
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', biz_page)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', biz_page)
    if not m:
        print("0")
        sys.exit(0)
    key = m.group(1)
    
    # Get Receipts Page
    r = s.get(f"{MANAGER_URL}/receipts?{key}")
    # Simple heuristic: count occurrences of row identifiers or specific patterns
    # Better: Manager usually shows "1 - 50 of X" or similar, or we count table rows
    count = r.text.count('<tr>') # Very rough proxy, but sufficient for differential comparison
    print(count)
except Exception:
    print("0")
EOF

python3 /tmp/get_initial_count.py > /tmp/initial_receipt_count.txt
echo "Initial receipt proxy count: $(cat /tmp/initial_receipt_count.txt)"

echo "=== Setup complete ==="