#!/bin/bash
echo "=== Exporting setup_service_item results ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to inspect Manager.io state via HTTP
python3 - <<'EOF' > /tmp/task_result.json
import requests
import re
import json
import time

MANAGER_URL = "http://localhost:8080"
OUTPUT = {
    "account_exists": False,
    "module_enabled": False,
    "item_exists": False,
    "item_code_correct": False,
    "item_price_correct": False,
    "item_linked_correctly": False,
    "invoice_exists": False,
    "invoice_total_correct": False,
    "invoice_line_correct": False,
    "captured_account_name": None,
    "captured_item_name": None
}

def clean_html(text):
    return re.sub(r'<[^>]+>', ' ', text)

def main():
    try:
        s = requests.Session()
        # Login
        s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"})
        
        # Get Business Key
        r = s.get(f"{MANAGER_URL}/businesses")
        m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
        if not m:
            m = re.search(r'start\?([^"&\s]+)', r.text)
        if not m:
            print(json.dumps(OUTPUT))
            return
        
        biz_key = m.group(1)
        s.get(f"{MANAGER_URL}/start?{biz_key}")
        
        # 1. Check if Module is Enabled
        # We check if the link exists in the sidebar or tabs page
        r_summary = s.get(f"{MANAGER_URL}/summary?{biz_key}")
        if "non-inventory-items" in r_summary.text.lower() or "Non-inventory Items" in r_summary.text:
            OUTPUT["module_enabled"] = True
            
        # 2. Check Chart of Accounts for "Consulting Revenue"
        r_coa = s.get(f"{MANAGER_URL}/chart-of-accounts?{biz_key}")
        # Look for the account name
        acc_match = re.search(r'>\s*Consulting Revenue\s*<', r_coa.text, re.IGNORECASE)
        consulting_acc_uuid = None
        
        if acc_match:
            OUTPUT["account_exists"] = True
            OUTPUT["captured_account_name"] = "Consulting Revenue"
            # Try to find the UUID. Usually in the Edit link: href="account-form?Key=UUID"
            # We need to find the specific row.
            # Simple regex to find UUID near the name
            # Pattern: <a href="account-form?Key=abcd...">Consulting Revenue</a>
            # or in a table row.
            # Let's try to extract the Edit link for this account
            # This regex looks for an href with Key=... followed by content containing Consulting Revenue
            link_match = re.search(r'href="[^"]*Key=([^"&]+)[^"]*">[^<]*Consulting Revenue', r_coa.text, re.IGNORECASE)
            if link_match:
                consulting_acc_uuid = link_match.group(1)
            else:
                # Fallback: look for the UUID in the row context
                lines = r_coa.text.split('\n')
                for i, line in enumerate(lines):
                    if "Consulting Revenue" in line:
                        # search backwards/forwards for UUID
                        context = "".join(lines[i-5:i+5])
                        u_m = re.search(r'Key=([a-f0-9-]+)', context)
                        if u_m:
                            consulting_acc_uuid = u_m.group(1)
                            break
                            
        # 3. Check Non-inventory Item
        r_items = s.get(f"{MANAGER_URL}/non-inventory-items?{biz_key}")
        item_match = re.search(r'>\s*Supply Chain Consulting\s*<', r_items.text, re.IGNORECASE)
        item_uuid = None
        
        if item_match:
            OUTPUT["item_exists"] = True
            OUTPUT["captured_item_name"] = "Supply Chain Consulting"
            
            # Find Item UUID to check details
            link_match = re.search(r'href="[^"]*Key=([^"&]+)[^"]*">[^<]*Supply Chain Consulting', r_items.text, re.IGNORECASE)
            if link_match:
                item_uuid = link_match.group(1)
                
            if item_uuid:
                # Fetch Item Details
                r_item_detail = s.get(f"{MANAGER_URL}/non-inventory-item-form?Key={item_uuid}&{biz_key}")
                
                # Check Code
                if "SVC-CONSULT" in r_item_detail.text:
                    OUTPUT["item_code_correct"] = True
                
                # Check Price (200)
                if 'value="200' in r_item_detail.text:
                    OUTPUT["item_price_correct"] = True
                    
                # Check Linked Account
                # The selected option in the dropdown will have selected="selected"
                # <option value="ACCOUNT_UUID" selected="selected">Consulting Revenue</option>
                if consulting_acc_uuid and consulting_acc_uuid in r_item_detail.text:
                     # Verify it is selected
                     # We look for value="UUID" followed by selected
                     if f'value="{consulting_acc_uuid}" selected' in r_item_detail.text or \
                        f'value="{consulting_acc_uuid}"' in r_item_detail.text: # Looser check if selected logic is complex js
                         OUTPUT["item_linked_correctly"] = True
        
        # 4. Check Invoice
        r_inv = s.get(f"{MANAGER_URL}/sales-invoices?{biz_key}")
        # Look for Ernst Handel and amount
        # This is a list.
        if "Ernst Handel" in r_inv.text:
             # We need to find the specific invoice to check line items
             # Look for edit link for an invoice for Ernst Handel
             # Regex: Row containing Ernst Handel ... 1,000.00
             # Note: Manager formats numbers 1,000.00
             
             # Extract Invoice Keys for Ernst Handel
             # Pattern: href="sales-invoice-view?Key=..." ... Ernst Handel
             inv_uuids = re.findall(r'href="sales-invoice-view\?Key=([^"&]+)[^"]*".*?Ernst Handel', r_inv.text, re.DOTALL)
             
             for inv_uuid in inv_uuids:
                 r_inv_view = s.get(f"{MANAGER_URL}/sales-invoice-view?Key={inv_uuid}&{biz_key}")
                 
                 # Check Total
                 if "1,000.00" in r_inv_view.text:
                     OUTPUT["invoice_total_correct"] = True
                     OUTPUT["invoice_exists"] = True
                     
                     # Check Line Item
                     if "Supply Chain Consulting" in r_inv_view.text:
                         OUTPUT["invoice_line_correct"] = True
                         break
                         
    except Exception as e:
        OUTPUT["error"] = str(e)

    print(json.dumps(OUTPUT))

if __name__ == "__main__":
    main()
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json