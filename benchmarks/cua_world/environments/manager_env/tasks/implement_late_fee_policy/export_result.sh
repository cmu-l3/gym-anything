#!/bin/bash
echo "=== Exporting implement_late_fee_policy results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python script to inspect Manager.io internal state via API
# We verify:
# - Account 'Late Fees Collected' exists
# - Non-inventory item 'Late Fee' exists and links to that account
# - Sales Invoice exists for 'Alfreds Futterkiste' using that item

cat > /tmp/inspect_manager.py << 'EOF'
import requests
import re
import json
import sys
import datetime

MANAGER_URL = "http://localhost:8080"
COOKIE_FILE = "/tmp/mgr_cookies.txt"

def get_session():
    s = requests.Session()
    # Login
    try:
        s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    except Exception as e:
        print(f"Login failed: {e}", file=sys.stderr)
        return None, None
    
    # Get Business Key for Northwind Traders
    try:
        r = s.get(f"{MANAGER_URL}/businesses")
        # Regex to find key for Northwind
        # Link looks like: <a href="/summary?Key=...">Northwind Traders</a>
        # or <a href="/start?Key=...">...
        m = re.search(r'Key=([^"&]+)[^>]*>Northwind Traders', r.text)
        if not m:
            # Fallback for older versions or if it's the only business
            m = re.search(r'Key=([^"&]+)', r.text)
        
        if m:
            key = m.group(1)
            # 'Enter' the business to set session context
            s.get(f"{MANAGER_URL}/start?Key={key}")
            return s, key
    except Exception as e:
        print(f"Failed to get business key: {e}", file=sys.stderr)
    
    return None, None

def inspect():
    session, key = get_session()
    results = {
        "account_created": False,
        "account_id": None,
        "item_created": False,
        "item_linked": False,
        "item_id": None,
        "invoice_created": False,
        "invoice_correct_item": False,
        "invoice_total": 0.0
    }

    if not session or not key:
        return results

    # 1. Check Chart of Accounts for "Late Fees Collected"
    # Endpoints typically follow the pattern /{object-type}?Key=...
    # We might need to fetch the list page and scrape, or use .json if available (Manager is mostly HTML)
    # Strategy: Fetch Chart of Accounts page, look for the name.
    
    try:
        r = session.get(f"{MANAGER_URL}/chart-of-accounts?Key={key}")
        if "Late Fees Collected" in r.text:
            results["account_created"] = True
            # Try to extract UUID if possible (complex regex needed)
            # Looking for <a href="/chart-of-account-form?Key=...&FileID=UUID">Late Fees Collected</a>
            # or similar structure.
            # UUID pattern: [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}
            m = re.search(r'Key=' + re.escape(key) + r'&amp;FileID=([0-9a-f-]{36})">Late Fees Collected', r.text)
            if not m:
                # Try unescaped
                m = re.search(r'Key=' + re.escape(key) + r'&FileID=([0-9a-f-]{36})">Late Fees Collected', r.text)
            
            if m:
                results["account_id"] = m.group(1)
                print(f"Found Account ID: {results['account_id']}")
    except Exception as e:
        print(f"Error checking accounts: {e}", file=sys.stderr)

    # 2. Check Non-inventory Items
    try:
        r = session.get(f"{MANAGER_URL}/non-inventory-items?Key={key}")
        if "Late Fee" in r.text and "LATE" in r.text:
            results["item_created"] = True
            # Extract Item UUID
            m = re.search(r'FileID=([0-9a-f-]{36})">LATE', r.text) # Usually code is linked or Name
            if not m:
                m = re.search(r'FileID=([0-9a-f-]{36})">Late Fee', r.text)
            
            if m:
                item_id = m.group(1)
                results["item_id"] = item_id
                print(f"Found Item ID: {item_id}")
                
                # Check link: Fetch the item edit page
                r_item = session.get(f"{MANAGER_URL}/non-inventory-item-form?Key={key}&FileID={item_id}")
                # Look for the Account ID selected in the form options
                if results["account_id"]:
                    # Check if the account ID is selected
                    # HTML: <option value="ACCOUNT_ID" selected="selected">
                    if f'value="{results["account_id"]}" selected' in r_item.text or \
                       f'value="{results["account_id"]}" selected="selected"' in r_item.text:
                        results["item_linked"] = True
    except Exception as e:
        print(f"Error checking items: {e}", file=sys.stderr)

    # 3. Check Sales Invoices
    try:
        r = session.get(f"{MANAGER_URL}/sales-invoices?Key={key}")
        # Look for Alfreds Futterkiste
        if "Alfreds Futterkiste" in r.text:
            # We need to find the specific invoice. It might be the most recent one.
            # Look for invoice links.
            # Regex for invoice rows containing "Alfreds Futterkiste"
            # This is hard to do robustly with regex on a table, but let's try finding the link closest
            
            # Find all invoice IDs
            invoice_ids = re.findall(r'sales-invoice-view\?Key=' + re.escape(key) + r'&amp;FileID=([0-9a-f-]{36})', r.text)
            if not invoice_ids:
                invoice_ids = re.findall(r'sales-invoice-view\?Key=' + re.escape(key) + r'&FileID=([0-9a-f-]{36})', r.text)
            
            # Check the most recent invoices (last few IDs)
            for inv_id in invoice_ids[:5]: # Check top 5
                r_inv = session.get(f"{MANAGER_URL}/sales-invoice-view?Key={key}&FileID={inv_id}")
                
                if "Alfreds Futterkiste" in r_inv.text:
                    results["invoice_created"] = True
                    
                    # Check Amount
                    if "50.00" in r_inv.text:
                         results["invoice_total"] = 50.0
                    
                    # Check if Item was used.
                    # The view mode might show description, but we want to know if the item object was used.
                    # We can check the "Edit" form of the invoice to be sure.
                    r_inv_edit = session.get(f"{MANAGER_URL}/sales-invoice-form?Key={key}&FileID={inv_id}")
                    
                    # In the edit form, there should be a reference to the Item ID
                    if results["item_id"] and results["item_id"] in r_inv_edit.text:
                        results["invoice_correct_item"] = True
                        break

    except Exception as e:
        print(f"Error checking invoices: {e}", file=sys.stderr)

    return results

if __name__ == "__main__":
    data = inspect()
    with open("/tmp/inspection_result.json", "w") as f:
        json.dump(data, f, indent=2)
EOF

# Run the python script
python3 /tmp/inspect_manager.py

# Combine results
RESULT_JSON=$(mktemp /tmp/result.XXXXXX.json)
INSPECTION_JSON="/tmp/inspection_result.json"

if [ -f "$INSPECTION_JSON" ]; then
    cat "$INSPECTION_JSON" > "$RESULT_JSON"
else
    echo '{"error": "Inspection failed"}' > "$RESULT_JSON"
fi

# Save to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$RESULT_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json