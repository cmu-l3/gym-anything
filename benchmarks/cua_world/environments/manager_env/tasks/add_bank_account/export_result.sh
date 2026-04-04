#!/bin/bash
echo "=== Exporting add_bank_account task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to extract bank account details
# We inspect the Manager.io state via HTTP requests to localhost
python3 - << 'PYEOF' > /tmp/task_result.json
import requests
import re
import json
import sys
import time

MANAGER_URL = "http://localhost:8080"
EXPECTED_NAME = "Business Checking"

result = {
    "account_found": False,
    "account_details": {},
    "total_accounts": 0,
    "initial_count": 0,
    "task_start_time": 0,
    "timestamp": time.time()
}

try:
    # Read setup data
    try:
        with open("/tmp/initial_count.txt", "r") as f:
            result["initial_count"] = int(f.read().strip())
    except:
        pass
        
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            result["task_start_time"] = int(f.read().strip())
    except:
        pass

    # Session setup
    s = requests.Session()
    
    # Login
    s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"})
    
    # Find Northwind Traders business key
    resp = s.get(f"{MANAGER_URL}/businesses")
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
    
    if not m:
        # Try fallback regex
        m = re.search(r'start\?([^"&\s]+)', resp.text)
        
    if m:
        biz_key = m.group(1)
        
        # Go to Bank Accounts list
        list_url = f"{MANAGER_URL}/bank-and-cash-accounts?{biz_key}"
        resp = s.get(list_url)
        html = resp.text
        
        # Simple count of accounts (heuristic based on table rows/edit links)
        # In Manager, Edit links look like <a href="bank-or-cash-account-form?Key=...">
        result["total_accounts"] = html.count("bank-or-cash-account-form?") // 2 # Links appear twice usually? Or just once.
        if result["total_accounts"] == 0:
             result["total_accounts"] = html.count('td class="text-left"') # Fallback counting
        
        # Find the specific account by name and get its Edit URL to inspect details
        # Pattern: <td ...>Business Checking</td>...<a href="bank-or-cash-account-form?Key=UUID...">
        # We look for the link associated with the name
        
        # Note: Parsing HTML with regex is brittle, but Manager.io has clean structure
        # We look for the Name in the HTML, then find the associated Edit link
        if EXPECTED_NAME in html:
            result["account_found"] = True
            
            # To verify details, we need to visit the Edit page for this account.
            # We search for the UUID key associated with the name
            # This regex looks for the edit link preceding or following the name
            # Manager list view: <tr><td>Name</td>...<td><a href="...">Edit</a></td></tr>
            
            # Let's try to extract all keys and names
            # Find all edit links: bank-or-cash-account-form?Key=...
            keys = re.findall(r'bank-or-cash-account-form\?Key=([a-zA-Z0-9-]+)', html)
            
            # Iterate through keys to find the one matching our target name
            for key in set(keys):
                edit_url = f"{MANAGER_URL}/bank-or-cash-account-form?Key={key}&{biz_key}"
                # We need to exclude the "New" link if it was captured, but regex demands Key=... which new doesn't have usually
                
                account_resp = s.get(edit_url)
                account_html = account_resp.text
                
                # Check if this is the account we want
                # Input value check: <input ... name="..." value="Business Checking">
                if f'value="{EXPECTED_NAME}"' in account_html:
                    # Found it! Extract other fields
                    details = {"Name": EXPECTED_NAME}
                    
                    # Extract Bank Name
                    # Look for input/textarea following "Bank Name" label or implicit structure
                    # Usually: <input ... value="First National Bank">
                    # We'll just grab values of inputs that might match
                    
                    # Specific extraction for Bank Name (often custom field or specific input)
                    # We check if the expected bank name exists in the form value
                    if 'value="First National Bank"' in account_html:
                        details["BankName"] = "First National Bank"
                    elif "First National Bank" in account_html:
                         details["BankName_Raw"] = "Found in text"
                         
                    # Extract Account Number
                    if 'value="1029384756"' in account_html:
                        details["AccountNumber"] = "1029384756"
                    elif "1029384756" in account_html:
                        details["AccountNumber_Raw"] = "Found in text"
                        
                    result["account_details"] = details
                    break

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="