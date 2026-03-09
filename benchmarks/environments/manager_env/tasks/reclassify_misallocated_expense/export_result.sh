#!/bin/bash
# Export script for reclassify_misallocated_expense
# Extracts current state of Accounts and Payments

echo "=== Exporting Results ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Python script to inspect Manager.io state
cat > /tmp/inspect_state.py << 'EOF'
import requests
import re
import json
import sys

BASE_URL = "http://localhost:8080"
SESSION = requests.Session()

def inspect():
    results = {
        "meals_account_exists": False,
        "meals_account_uuid": None,
        "target_payment_found": False,
        "target_payment_account": None,
        "target_payment_amount": 0,
        "office_supplies_balance": 0
    }

    try:
        # Login
        SESSION.post(f"{BASE_URL}/login", data={"Username": "administrator"})
        
        # Get Business
        resp = SESSION.get(f"{BASE_URL}/businesses")
        m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
        if not m:
            print("Business not found")
            return results
        biz_id = m.group(1)
        SESSION.get(f"{BASE_URL}/start?{biz_id}")

        # 1. Check for "Meals & Entertainment" account
        # We fetch the Chart of Accounts or Account List
        resp = SESSION.get(f"{BASE_URL}/chart-of-accounts?{biz_id}")
        
        # Look for the name
        if "Meals & Entertainment" in resp.text:
            results["meals_account_exists"] = True
            # Try to grab its UUID from the Edit link
            # Regex: <td...><a href="account-form?Key=UUID...">Edit</a>...Meals & Entertainment...
            # Note: HTML structure varies, trying robust match
            # Searching for the UUID associated with the name
            # Pattern: account-form?([^"]+)">Edit</a>[^<]*</td>[^<]*<td>Meals & Entertainment
            m_acc = re.search(r'account-form\?([^"]+)">Edit</a>[^<]*</td>[^<]*<td>Meals & Entertainment', resp.text)
            if m_acc:
                key_param = m_acc.group(1) # e.g. "Key=123-456..."
                results["meals_account_uuid"] = key_param.split('=')[-1]

        # 2. Find the "City Grill" payment
        # Fetch Payments list
        resp = SESSION.get(f"{BASE_URL}/payments?{biz_id}")
        
        # We need to find the link to the payment to inspect its details
        # Look for row with "City Grill" and "245.00"
        # Then grab the View/Edit link
        # Regex: <td...><a href="payment-view\?([^"]+)">...</a>...City Grill...245.00
        
        # Note: Manager lists might be paginated or structured differently.
        # We look for the "Key" in the link near "City Grill"
        
        # Simple string search first
        if "City Grill" in resp.text:
            results["target_payment_found"] = True
            
            # Extract key
            # Looking for: <a href="payment-view?Key=...">
            # Context: ...2025-05-15...City Grill...
            
            # Let's try to get the Edit Form for the City Grill payment to see the Account
            # We iterate over all Edit links? No, too many.
            # We search for the specific text block.
            
            lines = resp.text.split('\n')
            payment_key = None
            for i, line in enumerate(lines):
                if "City Grill" in line and "245.00" in line:
                    # Search backwards or in this line for the key
                    m_key = re.search(r'payment-view\?([^"]+)', line)
                    if m_key:
                        payment_key = m_key.group(1)
                        break
            
            if payment_key:
                # Fetch the payment details (Edit form has the raw data in the script tag or input)
                # view-form often renders the Account Name text, which is easier!
                resp_view = SESSION.get(f"{BASE_URL}/payment-view?{payment_key}")
                
                # Check what Account is listed in the view
                # It usually shows "Account" ... "Meals & Entertainment"
                if "Meals & Entertainment" in resp_view.text:
                    results["target_payment_account"] = "Meals & Entertainment"
                elif "Office Supplies" in resp_view.text:
                    results["target_payment_account"] = "Office Supplies"
                else:
                    # Fallback: regex for any account name
                    results["target_payment_account"] = "Unknown"

    except Exception as e:
        print(f"Error inspecting state: {e}")

    return results

if __name__ == "__main__":
    data = inspect()
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f, indent=2)
EOF

python3 /tmp/inspect_state.py
chmod 666 /tmp/task_result.json

echo "Export completed."
cat /tmp/task_result.json