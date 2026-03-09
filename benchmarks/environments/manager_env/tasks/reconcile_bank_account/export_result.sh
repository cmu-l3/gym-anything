#!/bin/bash
echo "=== Exporting reconcile_bank_account result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Python script to query the reconciliation data
cat > /tmp/check_reconciliation.py << 'PYEOF'
import requests
import re
import json
import sys
from datetime import datetime

BASE_URL = "http://localhost:8080"
SESSION = requests.Session()

def login():
    SESSION.post(f"{BASE_URL}/login", data={"Username": "administrator"}, allow_redirects=True)

def get_business_key(name="Northwind Traders"):
    resp = SESSION.get(f"{BASE_URL}/businesses")
    match = re.search(r'start\?([^"&\s]+)[^<]{0,300}' + re.escape(name), resp.text)
    if not match:
        match = re.search(r'start\?([^"&\s]+)', resp.text)
    return match.group(1) if match else None

def get_reconciliations(biz_key):
    # Manager.io lists reconciliations at /bank-reconciliations?Key=...
    url = f"{BASE_URL}/bank-reconciliations?{biz_key}"
    resp = SESSION.get(url)
    
    # We need to parse the HTML table to find the reconciliation
    # We are looking for: 
    # Date: 31/01/2025
    # Account: Petty Cash
    # Statement Balance: 170.00
    
    # A simple regex approach to extract rows
    # Rows usually look like: <tr>...<td>31/01/2025</td>...<td>Petty Cash</td>...<td>170.00</td>...</tr>
    
    reconciliations = []
    
    # Extract all rows from the table
    # This regex is a bit loose but should catch standard table rows
    row_pattern = re.compile(r'<tr[^>]*>(.*?)</tr>', re.DOTALL)
    rows = row_pattern.findall(resp.text)
    
    for row in rows:
        # Check for our target data in the row
        # Date format in Manager depends on settings, but usually dd/mm/yyyy for Northwind default
        # or yyyy-mm-dd
        
        has_date = "31/01/2025" in row or "2025-01-31" in row
        has_account = "Petty Cash" in row
        has_balance = "170.00" in row
        
        if has_date and has_account:
            rec_data = {
                "date_match": True,
                "account_match": True,
                "balance_match": has_balance,
                "raw_row": row[:100] + "..." # Snippet for debugging
            }
            reconciliations.append(rec_data)
            
    return reconciliations

def main():
    login()
    biz_key = get_business_key()
    if not biz_key:
        print(json.dumps({"error": "Business not found"}))
        return

    recs = get_reconciliations(biz_key)
    
    result = {
        "reconciliations_found": len(recs),
        "matches": recs,
        "business_key_found": True
    }
    
    with open("/tmp/task_result.json", "w") as f:
        json.dump(result, f)

if __name__ == "__main__":
    main()
PYEOF

# Run checker
python3 /tmp/check_reconciliation.py

# Add basic file info
OUTPUT_EXISTS="false"
if [ -f /tmp/task_result.json ]; then
    OUTPUT_EXISTS="true"
fi

# Clean up python script
rm /tmp/check_reconciliation.py

echo "Export complete."