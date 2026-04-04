#!/bin/bash
echo "=== Exporting record_prepaid_expense results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to inspect Manager.io state via HTTP
python3 - << 'EOF' > /tmp/task_result.json
import requests
import json
import re
import sys
import os

MANAGER_URL = "http://localhost:8080"
COOKIE_FILE = "/tmp/mgr_cookies.txt"

def get_result():
    s = requests.Session()
    
    # Login
    try:
        s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    except Exception as e:
        return {"error": str(e)}

    # Get Business Key
    try:
        if os.path.exists("/tmp/biz_key.txt"):
            with open("/tmp/biz_key.txt", "r") as f:
                biz_key = f.read().strip()
        else:
            # Fallback search
            biz_page = s.get(f"{MANAGER_URL}/businesses").text
            m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_page)
            if not m:
                m = re.search(r"start\?([^\"&\s]+)", biz_page)
            biz_key = m.group(1) if m else None
    except:
        biz_key = None

    if not biz_key:
        return {"error": "Could not determine business key"}

    # Navigate to business context
    s.get(f"{MANAGER_URL}/start?{biz_key}")

    # 1. Inspect Chart of Accounts / Balance Sheet
    # We need to find the "Prepaid Insurance" account and verify its type.
    # The structure of Manager URLs varies, but usually accounts are listed in Settings > Chart of Accounts
    # or visible in the Balance Sheet report.
    
    # Strategy: Get the "Chart of Accounts" page or "Summary" page source
    # The Summary page lists accounts. We can check if "Prepaid Insurance" appears under Assets.
    summary_page = s.get(f"{MANAGER_URL}/summary?{biz_key}").text
    
    account_exists = "Prepaid Insurance" in summary_page
    
    # To strictly verify it's an ASSET, we check if it appears in the "Assets" section of the HTML.
    # This is a bit brittle to parse via regex, but usually "Assets" header is followed by asset accounts
    # and then "Liabilities" header.
    
    is_asset = False
    if account_exists:
        # Simple heuristic: It should be before "Liabilities" and "Equity" and "Income" in the Summary page
        # Manager Summary order: Assets, Liabilities, Equity, Income, Expenses
        # We find the position of "Prepaid Insurance" relative to "Liabilities"
        try:
            pos_account = summary_page.find("Prepaid Insurance")
            pos_liabilities = summary_page.find("Liabilities")
            pos_equity = summary_page.find("Equity")
            
            # If "Liabilities" isn't present (e.g. none exist), check Equity
            limit_pos = pos_liabilities if pos_liabilities > 0 else pos_equity
            
            if pos_account > 0 and (limit_pos < 0 or pos_account < limit_pos):
                is_asset = True
        except:
            pass

    # 2. Inspect Payments
    # Get the Payments list
    payments_page = s.get(f"{MANAGER_URL}/payments?{biz_key}").text
    
    # We look for a row containing the date (optional), Description/Payee, and Amount
    # Manager lists payments with columns. 
    # We can try to extract the UUID of the payment to drill down, or just regex the list.
    
    payment_found = False
    payee_correct = False
    amount_correct = False
    allocation_correct = False
    
    # Regex to find a payment row: 
    # Look for "Fairfax Insurance"
    if "Fairfax Insurance" in payments_page:
        payee_correct = True
        
        # Look for 2,400.00 or 2400.00 near it
        # Manager formats numbers typically like "2,400.00"
        if "2,400.00" in payments_page or "2400.00" in payments_page:
            amount_correct = True
            payment_found = True
            
            # For allocation check, we really need to open the payment or check the text
            # If the payment list shows the "Account" column, we can check there.
            # Often the Summary description is shown.
            # However, seeing "Prepaid Insurance" in the Payments tab row is a good proxy if visible.
            # Alternatively, we can assume if the Account Balance in Summary is 2,400.00, it's allocated.
            
            # Check Balance of Prepaid Insurance in Summary
            # We look for "Prepaid Insurance" followed closely by "2,400.00"
            # This confirms the transaction hit the account.
            pattern = r"Prepaid Insurance.*?2,400\.00"
            if re.search(pattern, summary_page, re.DOTALL):
                allocation_correct = True

    return {
        "account_exists": account_exists,
        "is_asset": is_asset,
        "payment_found": payment_found,
        "payee_correct": payee_correct,
        "amount_correct": amount_correct,
        "allocation_correct": allocation_correct,
        "timestamp": os.popen("date +%s").read().strip()
    }

print(json.dumps(get_result(), indent=2))
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="