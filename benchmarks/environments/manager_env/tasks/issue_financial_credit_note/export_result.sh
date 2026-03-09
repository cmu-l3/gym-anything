#!/bin/bash
echo "=== Exporting task results ==="

# Source utils for screenshot
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python extraction script to check Manager.io state
# We use Python here because parsing the HTML/API of Manager is complex in Bash
python3 - << 'EOF' > /tmp/extraction_log.txt 2>&1
import requests
import re
import json
import sys
import time

MANAGER_URL = "http://localhost:8080"
RESULT_FILE = "/tmp/task_result.json"

def extract_key(html, pattern):
    m = re.search(pattern, html)
    return m.group(1) if m else None

def main():
    s = requests.Session()
    
    # Login
    try:
        r = s.get(f"{MANAGER_URL}/", timeout=10)
        if "Login" in r.text or "login" in r.text.lower():
            s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    except Exception as e:
        print(f"Connection failed: {e}")
        save_result(success=False, error="Could not connect to Manager")
        return

    # Get Business Key for Northwind
    r = s.get(f"{MANAGER_URL}/businesses")
    # Regex to find the key for "Northwind Traders"
    # Links look like /start?FileID=... or /start?Key=...
    # We look for the link associated with the text
    biz_key = None
    lines = r.text.split('\n')
    for i, line in enumerate(lines):
        if "Northwind Traders" in line:
            # Look backwards or forwards for the link
            context = "\n".join(lines[max(0, i-5):min(len(lines), i+5)])
            m = re.search(r'start\?([^"&\s]+)', context)
            if m:
                biz_key = m.group(1)
                break
    
    if not biz_key:
        # Fallback: try to find any key
        m = re.search(r'start\?([^"&\s]+)', r.text)
        if m:
            biz_key = m.group(1)

    if not biz_key:
        print("Could not find business key")
        save_result(success=False, error="Business not found")
        return

    print(f"Using Business Key: {biz_key}")
    
    # 1. Check Chart of Accounts for "Volume Discounts"
    r = s.get(f"{MANAGER_URL}/chart-of-accounts?{biz_key}")
    account_created = "Volume Discounts" in r.text
    print(f"Account 'Volume Discounts' found: {account_created}")

    # 2. Check Credit Notes
    r = s.get(f"{MANAGER_URL}/credit-notes?{biz_key}")
    
    credit_note_found = False
    correct_customer = False
    correct_amount = False
    no_inventory_item = False
    allocated_correctly = False
    
    # Find the row for Alfreds Futterkiste
    # This is a heuristic scrape of the list page
    if "Alfreds Futterkiste" in r.text:
        correct_customer = True
        if "500.00" in r.text:
            correct_amount = True
            
            # Now we need to drill down to verify lines. 
            # Find the View or Edit link for this credit note.
            # Look for a link like /credit-note-view?Key=... near the text
            # We split by "Alfreds Futterkiste" and look at the preceding link
            parts = r.text.split("Alfreds Futterkiste")
            
            # The link usually appears before the name in the table row
            # We look at the html chunk before the name
            # Pattern: <a href="credit-note-view?Key=UUID">...</a> ... <td>Alfreds...
            
            # Try to find all credit note view links
            view_links = re.findall(r'href="credit-note-view\?([^"]+)"', r.text)
            
            for link_key in view_links:
                # Fetch the credit note detail
                cn_url = f"{MANAGER_URL}/credit-note-view?{link_key}"
                r_cn = s.get(cn_url)
                
                # Check if this is the right one (customer + amount)
                if "Alfreds Futterkiste" in r_cn.text and "500.00" in r_cn.text:
                    credit_note_found = True
                    
                    # Check allocation
                    # If an inventory item was used, the Item Name/Code usually appears
                    # If an account was used, "Volume Discounts" should appear in the description/account column
                    
                    if "Volume Discounts" in r_cn.text:
                        allocated_correctly = True
                    
                    # To be strict about "No Inventory Item", we check if typical inventory fields are absent 
                    # or if the text "Inventory - sales" (default account for items) is NOT present 
                    # if the user didn't map it differently.
                    # A better check: The 'Item' column on the view page is usually distinct.
                    # However, simply ensuring 'Volume Discounts' is present is a strong signal 
                    # because you can't select that Account if you select an Item (the Item drives the account).
                    
                    if allocated_correctly:
                        no_inventory_item = True # Strong proxy
                    
                    break

    save_result(
        success=True,
        account_created=account_created,
        credit_note_found=credit_note_found,
        correct_customer=correct_customer,
        correct_amount=correct_amount,
        no_inventory_item=no_inventory_item,
        allocated_correctly=allocated_correctly
    )

def save_result(**kwargs):
    with open(RESULT_FILE, 'w') as f:
        json.dump(kwargs, f)

if __name__ == "__main__":
    main()
EOF

# 3. Read the result python generated
if [ -f /tmp/task_result.json ]; then
    cat /tmp/task_result.json
else
    echo '{"success": false, "error": "Extraction script failed"}' > /tmp/task_result.json
fi

# Add timestamp info
TASK_START=$(cat /tmp/manager_task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Merge timestamps into json (using python one-liner)
python3 -c "import json; d=json.load(open('/tmp/task_result.json')); d.update({'task_start': $TASK_START, 'task_end': $TASK_END}); print(json.dumps(d))" > /tmp/task_result_final.json
mv /tmp/task_result_final.json /tmp/task_result.json

# Cleanup
rm -f /tmp/extraction_log.txt

echo "=== Export complete ==="