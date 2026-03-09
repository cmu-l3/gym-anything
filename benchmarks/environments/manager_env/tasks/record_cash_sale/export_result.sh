#!/bin/bash
# Export script for record_cash_sale task

echo "=== Exporting record_cash_sale results ==="

# Source utils for screenshot
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python script to inspect Manager.io state and extract the receipt
# We look for the most recent receipt created after task start
cat << 'EOF' > /tmp/inspect_receipt.py
import requests
import re
import json
import time
import os
import sys

MANAGER_URL = "http://localhost:8080"
TASK_START_FILE = "/tmp/task_start_time.txt"

def get_task_start_time():
    try:
        if os.path.exists(TASK_START_FILE):
            with open(TASK_START_FILE, 'r') as f:
                return float(f.read().strip())
    except:
        pass
    return 0

def run_inspection():
    result = {
        "receipt_found": False,
        "details": {},
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
            return result
        key = m.group(1)
        
        # Get Receipts List
        receipts_page = s.get(f"{MANAGER_URL}/receipts?{key}").text
        
        # Find links to receipts (view-receipt?Key=...)
        # We look for the most recent ones. Manager lists usually show newest first or last depending on sort.
        # We will scan all receipts on the first page.
        # Regex to find receipt links and text
        # Link pattern: <a href="/view-receipt?Key=...">
        
        receipt_links = re.findall(r'href="(/view-receipt\?Key=[^"]+)"', receipts_page)
        
        # Check specific receipts
        target_found = False
        
        # We are looking for specific criteria, so we iterate through recent receipts
        # to find one that matches our expectations.
        for link in receipt_links[:10]: # Check top 10
            r_detail = s.get(f"{MANAGER_URL}{link}")
            html = r_detail.text
            
            # Extract basic fields via regex from the view page
            # Note: Manager view pages are HTML.
            
            # Payer
            payer_m = re.search(r'<div>Payer</div>\s*<div[^>]*>(.*?)</div>', html, re.DOTALL)
            payer = payer_m.group(1).strip() if payer_m else ""
            
            # Date
            date_m = re.search(r'<div>Date</div>\s*<div[^>]*>(.*?)</div>', html, re.DOTALL)
            date_str = date_m.group(1).strip() if date_m else ""
            
            # Bank Account
            # Usually listed in the header or a field "Received in"
            # It might just be in the summary or title.
            # In view mode, it might say "Cash Receipt - Cash on Hand"
            account_m = re.search(r'<div>Received in</div>\s*<div[^>]*>(.*?)</div>', html, re.DOTALL)
            account = account_m.group(1).strip() if account_m else ""
            
            # Line Items
            # Look for "Chai" and "12"
            # This is a bit loose, but we check if the text appears in the table rows
            has_chai = "Chai" in html
            has_qty_12 = "12" in html
            
            # Direct Sale Check: Ensure it's not linked to Accounts Receivable
            # If linked to AR, the line item usually describes the Invoice # or "Accounts receivable"
            is_ar_linked = "Accounts receivable" in html
            
            # Match Logic
            if "Walk-in" in payer or "Walk-in Customer" in payer:
                result["receipt_found"] = True
                result["details"] = {
                    "payer": payer,
                    "date": date_str,
                    "account": account,
                    "has_chai": has_chai,
                    "has_qty_12": has_qty_12,
                    "is_ar_linked": is_ar_linked,
                    "full_text_snippet": html[:1000] # Debug
                }
                target_found = True
                break
        
        if not target_found:
             result["error"] = "No receipt found matching 'Walk-in' payer"

    except Exception as e:
        result["error"] = str(e)
        
    return result

if __name__ == "__main__":
    res = run_inspection()
    with open("/tmp/task_result.json", "w") as f:
        json.dump(res, f, indent=2)
EOF

# Run the inspection script
python3 /tmp/inspect_receipt.py

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="