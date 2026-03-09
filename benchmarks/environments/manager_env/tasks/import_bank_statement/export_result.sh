#!/bin/bash
# Export script for import_bank_statement task
# Scrapes Manager.io pages to verify imported transactions

echo "=== Exporting import_bank_statement results ==="

source /workspace/scripts/task_utils.sh

# 1. capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python script to scrape Manager.io data
# We use Python here because parsing HTML/JSON from the API is easier than bash
python3 - << 'PYEOF' > /tmp/task_result.json
import requests
import re
import json
import time
import sys

MANAGER_URL = "http://localhost:8080"
OUTPUT = {
    "task_start_timestamp": 0,
    "final_timestamp": int(time.time()),
    "account_found": False,
    "transaction_count": 0,
    "found_descriptions": [],
    "found_amounts": [],
    "screenshot_exists": False
}

try:
    # Get task start time
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            OUTPUT["task_start_timestamp"] = int(f.read().strip())
    except:
        pass

    # Check screenshot
    try:
        import os
        if os.path.exists("/tmp/task_final.png"):
            OUTPUT["screenshot_exists"] = True
    except:
        pass

    # Create session
    s = requests.Session()
    
    # Login (if needed, usually auto-login as admin works or just hitting the page)
    # Try to hit the main page to get cookies/session
    r = s.get(f"{MANAGER_URL}/", allow_redirects=True)
    
    # Find the Business (Northwind Traders)
    # Look for link like /start?Key=...
    # We want the specific business key
    biz_key = None
    if "Northwind Traders" in r.text:
        m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
        if not m:
             m = re.search(r'start\?([^"&\s]+)', r.text)
        if m:
            biz_key = m.group(1)
    
    if not biz_key:
        # Try to login specifically if we didn't get straight in
        s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"})
        r = s.get(f"{MANAGER_URL}/businesses")
        m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
        if m:
            biz_key = m.group(1)

    if biz_key:
        # Navigate to Bank Accounts to find "Cash on Hand" key
        r = s.get(f"{MANAGER_URL}/bank-and-cash-accounts?{biz_key}")
        
        # Find the link to the Cash on Hand account view
        # It usually looks like <a href="/bank-account-view?Key=...">Cash on Hand</a>
        # Or checking the grid.
        # We look for the UUID associated with "Cash on Hand"
        # The structure is often complex tables. We'll search for the text and grab nearby link.
        
        # Regex to find the View/History link for Cash on Hand
        # Pattern: href="...Key=UUID..." ... Cash on Hand
        # Or href="...Key=UUID..." inside a row that contains Cash on Hand
        
        # Let's try to find the UUID directly.
        # It's a GUID.
        
        # Simpler approach: Iterate all links with 'bank-or-cash-account-view' (or similar)
        # and check their content.
        
        # However, checking the transaction count directly from the summary page is easier if possible.
        # The summary page shows "Statement Balance" or similar.
        # But we want to check individual transactions.
        
        # Let's try to get the UUID for "Cash on Hand".
        # We can list accounts via API if possible, or scrape.
        # Since we just need verification, let's look for the link in the HTML.
        
        # Find all keys in links
        keys = re.findall(r'Key=([a-f0-9-]+)', r.text)
        
        cash_account_key = None
        # This is a bit "blind", but we can iterate keys and fetch them to see if it's the right account
        # Optimization: Look at the text preceding or following the key in HTML source
        
        # Using a crude but effective parser: split by "Cash on Hand", look backwards for "Key="
        parts = r.text.split("Cash on Hand")
        if len(parts) > 1:
            # Look at the part before
            preceding = parts[0]
            # Find the last "Key="
            matches = re.findall(r'Key=([a-f0-9-]+)', preceding)
            if matches:
                cash_account_key = matches[-1]
                OUTPUT["account_found"] = True

        if cash_account_key:
            # Fetch the account transactions view
            # The view URL is typically /bank-or-cash-account-view?Key=...
            # Manager URL structures change, but let's try standard patterns
            
            # Pattern 1: /bank-or-cash-account-view
            url = f"{MANAGER_URL}/bank-or-cash-account-view?Key={cash_account_key}&FileID={biz_key}"
            # Note: FileID or similar might be part of the Key or query params. 
            # Manager uses the 'Key' param which often encodes the path.
            # Actually, the Key usually suffices.
            
            r_acct = s.get(f"{MANAGER_URL}/bank-or-cash-account-view?Key={cash_account_key}")
            
            # If that didn't work (404), try just the key or look for other links
            if r_acct.status_code != 200:
                # Try finding the exact URL from the previous page
                link_match = re.search(r'href="([^"]+Key=' + cash_account_key + r'[^"]*)"', r.text)
                if link_match:
                    url = f"{MANAGER_URL}/{link_match.group(1)}"
                    r_acct = s.get(url)

            if r_acct.status_code == 200:
                html = r_acct.text
                
                # Count rows in the table (roughly)
                # Each transaction is usually a <tr>
                # We can count occurrences of dates or known description parts
                
                OUTPUT["found_descriptions"] = []
                # Check for expected descriptions
                expected_desc = [
                    "Alfreds Futterkiste INV-001",
                    "Exotic Liquids - PO-2024-001",
                    "Office rent payment",
                    "City Power & Light",
                    "Ernst Handel INV-002",
                    "Staples order",
                    "Alfreds Futterkiste INV-003",
                    "Bank service charges"
                ]
                
                for desc in expected_desc:
                    if desc in html:
                        OUTPUT["found_descriptions"].append(desc)
                
                # Count amounts
                # Note: Manager formats amounts nicely (e.g. 2,500.00)
                # We check for the raw strings
                expected_amts = ["2,500.00", "1,800.00", "1,200.00", "350.00", "4,200.00", "275.50", "1,850.00", "45.00"]
                for amt in expected_amts:
                    if amt in html:
                        OUTPUT["found_amounts"].append(amt)
                        
                # Estimate total transactions based on found unique descriptions
                # (This is safer than counting TRs which might include headers/footers)
                OUTPUT["transaction_count"] = len(OUTPUT["found_descriptions"])

except Exception as e:
    OUTPUT["error"] = str(e)

print(json.dumps(OUTPUT))
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="