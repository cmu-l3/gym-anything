#!/bin/bash
echo "=== Exporting record_customer_refund result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to scrape the final state from Manager.io
python3 - << 'EOF' > /tmp/task_result.json
import requests
import re
import json
import sys

MANAGER_URL = "http://localhost:8080"
INITIAL_COUNT_FILE = "/tmp/initial_payment_count.txt"

def get_initial_count():
    try:
        with open(INITIAL_COUNT_FILE, 'r') as f:
            return int(f.read().strip())
    except:
        return 0

result = {
    "initial_count": get_initial_count(),
    "final_count": 0,
    "payment_found": False,
    "payment_details": {},
    "error": None
}

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
        result["error"] = "Could not find business key"
        print(json.dumps(result))
        sys.exit(0)
        
    biz_key = m.group(1)
    
    # Get Payments List
    payments_url = f"{MANAGER_URL}/payments?{biz_key}"
    resp = s.get(payments_url)
    html = resp.text
    
    # Count payments (looking for View links)
    # Manager.io lists usually have a View button/link for each item
    # Regex for UUID keys
    payment_keys = re.findall(r'View\?Key=([a-f0-9-]+)', html)
    result["final_count"] = len(payment_keys)
    
    # If we have payments, inspect the most recent one (assuming it's at the top or bottom)
    # Manager.io usually sorts by date, but let's check the last few to be safe if the user messed up the date
    # However, usually the newest ID is sufficient if we check content.
    
    # We will check the details of ALL payments found to find a match
    # This is robust against sorting issues.
    
    for key in payment_keys:
        view_url = f"{MANAGER_URL}/payment-view?Key={key}&{biz_key}"
        detail_resp = s.get(view_url)
        d_html = detail_resp.text
        
        # Simple string matching in the detail view
        # This is safer than fragile DOM parsing for a simple verification
        
        # Check Payee (Customer)
        # It should say "Alfreds Futterkiste"
        payee_match = "Alfreds Futterkiste" in d_html
        
        # Check Account
        # Should textually contain "Accounts receivable"
        account_match = "Accounts receivable" in d_html
        
        # Check Amount
        # Should contain "50.00"
        amount_match = "50.00" in d_html
        
        # Check Source Account
        # Should contain "Cash on Hand"
        source_match = "Cash on Hand" in d_html
        
        if payee_match and amount_match:
            result["payment_found"] = True
            result["payment_details"] = {
                "key": key,
                "payee_correct": payee_match,
                "account_correct": account_match,
                "amount_correct": amount_match,
                "source_correct": source_match
            }
            break

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="