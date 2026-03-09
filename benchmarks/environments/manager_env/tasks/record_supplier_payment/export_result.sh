#!/bin/bash
# Export script for record_supplier_payment task
# Scrapes Manager.io to find the newly created payment and exports details to JSON

echo "=== Exporting record_supplier_payment result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to inspect Manager.io data
# This script logs in, finds the Northwind business, and looks for the target payment
python3 - << 'PY_EOF'
import requests
import re
import json
import sys
import datetime

MANAGER_URL = "http://localhost:8080"
RESULT_FILE = "/tmp/task_result.json"

def extract_field(html, label):
    """Simple regex helper to extract field values from view page HTML."""
    # Pattern looks for the label and then the value in the following dd or div
    pattern = re.compile(f"{label}</div>\s*<div[^>]*>(.*?)</div>", re.IGNORECASE | re.DOTALL)
    m = pattern.search(html)
    if m:
        return m.group(1).strip()
    return ""

def main():
    result = {
        "payment_found": False,
        "details": {},
        "error": None,
        "timestamp": datetime.datetime.now().isoformat()
    }

    try:
        s = requests.Session()
        
        # 1. Login
        s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"})
        
        # 2. Find Northwind Traders business key
        biz_page = s.get(f"{MANAGER_URL}/businesses").text
        # Look for the key associated with "Northwind Traders"
        m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', biz_page)
        if not m:
            # Fallback to any business if Northwind specific logic fails
            m = re.search(r'start\?([^"&\s]+)', biz_page)
        
        if not m:
            result["error"] = "Could not find Northwind Traders business"
            with open(RESULT_FILE, 'w') as f:
                json.dump(result, f)
            return

        biz_key = m.group(1)
        
        # 3. Get Payments List
        # We need to find the specific payment. Since we don't have an ID, we search the list.
        # We look for a payment that matches our criteria: 2750.00 and Exotic Liquids
        payments_page = s.get(f"{MANAGER_URL}/payments?{biz_key}").text
        
        # Regex to find rows. This is brittle but standard for scraping without API.
        # We look for the "View" link which contains the payment key
        # <td class="...">20/01/2024</td>...Exotic Liquids...2,750.00
        
        # Let's try to find the specific payment view link based on content
        # We look for a row containing "2,750.00" and "Exotic Liquids"
        # Then extract the href to view it.
        
        lines = payments_page.split('</tr>')
        target_view_url = None
        
        for line in lines:
            if "2,750.00" in line and "Exotic Liquids" in line:
                # Found a potential match, extract the view link
                # href="view-payment?KEY..."
                link_match = re.search(r'href="(view-payment\?[^"]+)"', line)
                if link_match:
                    target_view_url = link_match.group(1)
                    break
        
        if not target_view_url:
            # Try looser match (just amount)
            for line in lines:
                if "2,750.00" in line:
                     link_match = re.search(r'href="(view-payment\?[^"]+)"', line)
                     if link_match:
                        target_view_url = link_match.group(1)
                        # We don't break here to prefer the stronger match above if it existed, 
                        # but since we didn't find it, we take this one.
                        break

        if target_view_url:
            result["payment_found"] = True
            
            # 4. Get Payment Details
            view_page = s.get(f"{MANAGER_URL}/{target_view_url}").text
            
            # Parse fields using simple scraping
            # Note: Manager.io DOM structure varies, but usually fields are in formatted divs
            
            # Extract Date (Format: 20/01/2024 or 2024-01-20)
            date_match = re.search(r'(\d{1,2}/\d{1,2}/\d{4})|(\d{4}-\d{2}-\d{2})', view_page)
            result["details"]["date"] = date_match.group(0) if date_match else ""
            
            # Extract Amount
            # Usually prominent
            if "2,750.00" in view_page:
                result["details"]["amount"] = 2750.00
            
            # Extract Payee
            if "Exotic Liquids" in view_page:
                result["details"]["payee"] = "Exotic Liquids"
                
            # Extract Description
            if "Payment for January beverage shipment" in view_page:
                 result["details"]["description"] = "Payment for January beverage shipment"
            
            # Extract Bank Account (Paid from)
            if "Cash on Hand" in view_page:
                result["details"]["bank_account"] = "Cash on Hand"
                
            # Extract Line Account
            if "Accounts payable" in view_page:
                result["details"]["line_account"] = "Accounts payable"

    except Exception as e:
        result["error"] = str(e)

    with open(RESULT_FILE, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == "__main__":
    main()
PY_EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json