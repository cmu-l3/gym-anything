#!/bin/bash
echo "=== Exporting Capital Accounts Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We use a Python script to interact with the Manager.io local instance
# to fetch the state of Capital Accounts and Receipts.
# This avoids fragile HTML parsing with grep/sed.

cat > /tmp/inspect_manager_state.py << 'PYEOF'
import requests
import json
import re
import sys
import os
from datetime import datetime

BASE_URL = "http://localhost:8080"
COOKIE_FILE = "/tmp/mgr_cookies.txt"

def get_business_key(session):
    # Fetch list of businesses
    try:
        resp = session.get(f"{BASE_URL}/businesses")
        # Extract the key for Northwind Traders
        # Link looks like: <a href="/summary?Key=...">Northwind Traders</a>
        # Or redirect URL: /start?Key=...
        match = re.search(r'Key=([a-zA-Z0-9-]+)[^"]*">Northwind Traders', resp.text)
        if not match:
            # Try generic search if name slightly different or if already redirected
            match = re.search(r'Key=([a-zA-Z0-9-]+)', resp.text)
        
        return match.group(1) if match else None
    except Exception as e:
        print(f"Error getting business key: {e}", file=sys.stderr)
        return None

def main():
    s = requests.Session()
    
    # 1. Login (if needed)
    s.post(f"{BASE_URL}/login", data={"Username": "administrator"})
    
    # 2. Get Business Key
    key = get_business_key(s)
    if not key:
        print(json.dumps({"error": "Could not find business key"}))
        return

    result = {
        "business_key": key,
        "module_enabled": False,
        "accounts": [],
        "receipts": [],
        "cash_balance": 0.0
    }

    # 3. Check if Capital Accounts module is enabled
    # We check the Summary page or the Tabs page to see if the link exists in the sidebar/tabs
    summary_resp = s.get(f"{BASE_URL}/summary?Key={key}")
    if "Capital Accounts" in summary_resp.text and "/capital-accounts?Key=" in summary_resp.text:
        result["module_enabled"] = True

    # 4. Fetch Capital Accounts
    if result["module_enabled"]:
        cap_resp = s.get(f"{BASE_URL}/capital-accounts?Key={key}")
        # Simple parsing of the HTML table for names and balances
        # We look for rows. This is rough but effective for verification.
        # Structure: <td>Maria Chen</td> ... <td>50,000.00</td>
        
        # Regex to find names and balances roughly
        # This assumes standard table formatting in Manager.io
        # We look for the name, then some HTML, then the balance
        for name in ["Maria Chen", "David Chen"]:
            # Check existence
            if name in cap_resp.text:
                # Try to extract balance
                # Context: <td>Maria Chen</td> ... <td ...>50,000.00</td>
                # We'll just look for the number in the vicinity if possible, or just confirm existence for now
                # and check balances via the Summary or specific account drill-down if needed.
                # A safer way is checking the Summary page for the "Capital Accounts" section
                
                # Let's try to extract from the Capital Accounts list page using a robust regex
                # Look for Name, then eventually a closing td, then opening td for code (optional), then balance
                # Manager tables are dynamic, but the name should be there.
                
                # Fetch detailed balance from the Summary page is often easier as it aggregates
                pass

        # Alternative: Parse the text content more broadly
        # We will iterate known partners and check their presence
        pass

    # 5. Fetch Receipts to verify transactions
    # We want to see receipts for 50000 and 75000
    rec_resp = s.get(f"{BASE_URL}/receipts?Key={key}")
    
    receipt_data = []
    # Look for amounts in the receipt list
    for amount in ["50,000.00", "75,000.00"]:
        if amount in rec_resp.text:
            receipt_data.append({"amount_found": amount})
    result["receipts"] = receipt_data

    # 6. Specific Account Verification (Drill down)
    # We can try to access the edit screens or view screens if we knew IDs, but we don't.
    # instead, let's look at the "Capital Accounts" summary page again.
    # We will grab all text and look for "Maria Chen ... 50,000.00" pattern
    
    cap_text = s.get(f"{BASE_URL}/capital-accounts?Key={key}").text
    
    accounts_found = []
    if "Maria Chen" in cap_text:
        # Check balance
        bal = 0.0
        # Search for 50,000.00 nearby? 
        # Actually, let's just check if the text "50,000.00" appears in the page 
        # AND "Maria Chen" appears. It's a loose check but acceptable combined with receipts.
        accounts_found.append({"name": "Maria Chen", "present": True})
    
    if "David Chen" in cap_text:
        accounts_found.append({"name": "David Chen", "present": True})
        
    result["accounts"] = accounts_found
    
    # 7. Check Bank Account Balance (Cash on Hand)
    # Get Summary page
    summary_text = s.get(f"{BASE_URL}/summary?Key={key}").text
    # Look for "Cash on Hand" followed by balance
    # Pattern: <div>Cash on Hand</div>...<div>125,000.00</div>
    # or inside a table.
    
    # Let's just dump the text of the Summary page and Capital Accounts page to the result 
    # for the verifier to parse with more powerful Python logic (BeautifulSoup is not installed, 
    # but string searching works).
    
    # Actually, we can just return raw booleans for the specific strings we expect
    result["raw_capital_page_content"] = cap_text
    result["raw_summary_page_content"] = summary_text
    result["raw_receipts_page_content"] = rec_resp.text

    print(json.dumps(result))

if __name__ == "__main__":
    main()
PYEOF

# Run the python script
echo "Running inspection script..."
python3 /tmp/inspect_manager_state.py > /tmp/task_result.json 2>/tmp/inspection_error.log

# Add file timestamps for anti-gaming
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Update json with timestamps
jq --arg start "$TASK_START" --arg end "$TASK_END" \
   '. + {task_start: $start, task_end: $end}' \
   /tmp/task_result.json > /tmp/task_result_final.json

mv /tmp/task_result_final.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json