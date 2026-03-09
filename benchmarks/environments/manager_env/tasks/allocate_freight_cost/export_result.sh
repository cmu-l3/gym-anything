#!/bin/bash
echo "=== Exporting allocate_freight_cost result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to scrape the specific invoice details from Manager.io
# Since Manager.io doesn't have a simple JSON API for this version, we scrape the HTML result
cat > /tmp/scrape_result.py << 'EOF'
import requests
import re
import json
import sys
import os

BASE_URL = "http://localhost:8080"
TIMEOUT = 10

result = {
    "invoice_found": False,
    "supplier": None,
    "description": None,
    "total_amount": 0.0,
    "line_items": [],
    "is_new": False
}

def clean_html(raw_html):
    return re.sub(r'<[^>]+>', '', raw_html).strip()

try:
    # 1. Get Business Key
    r = requests.get(f"{BASE_URL}/businesses", timeout=TIMEOUT)
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', r.text)
    
    if m:
        key = m.group(1)
        
        # 2. Get Purchase Invoices List
        r_list = requests.get(f"{BASE_URL}/purchase-invoices?{key}", timeout=TIMEOUT)
        
        # Find links to invoices. Pattern: <a href="purchase-invoice-view?Key=...">
        # We look for the most recent ones.
        invoice_links = re.findall(r'href="(purchase-invoice-view\?[^"]+)"', r_list.text)
        
        # Check the last few invoices (assuming the new one is at the bottom or top depending on sort)
        # We'll scan all found in the list to find the match
        for link in invoice_links:
            view_url = f"{BASE_URL}/{link}"
            r_view = requests.get(view_url, timeout=TIMEOUT)
            html = r_view.text
            
            # Extract Details
            # Supplier
            supplier_match = re.search(r'<div>Exotic Liquids</div>', html)
            if not supplier_match:
                # Try finding it in the form/table text
                if "Exotic Liquids" in html:
                    supplier_match = True
            
            # Amount
            # Look for totals like 45.00
            if "45.00" in html and supplier_match:
                result["invoice_found"] = True
                result["supplier"] = "Exotic Liquids"
                result["total_amount"] = 45.00
                
                # Extract Line Items
                # This is tricky with raw regex on HTML, searching for "Chang" near "45.00"
                if "Chang" in html:
                    # Check for Quantity. 
                    # If it's a value-only invoice, Qty might be empty in the view or not shown.
                    # Or shown as blank.
                    
                    # Heuristic: Check if "1" (qty) appears near "Chang"
                    # In Manager view, columns usually are: Item | Description | Qty | Unit Price | Amount
                    # If Qty is 0/blank, the view typically shows just the Amount or blank Qty
                    
                    qty_1_pattern = re.search(r'Chang.*?<td[^>]*>\s*1\s*</td>', html, re.DOTALL)
                    qty_val = 1 if qty_1_pattern else 0
                    
                    result["line_items"].append({
                        "item": "Chang",
                        "amount": 45.00,
                        "qty": qty_val
                    })
                break

except Exception as e:
    result["error"] = str(e)

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

# Run the scraper
python3 /tmp/scrape_result.py

# Add app running status
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Append/Merge metadata to result
jq --arg app "$APP_RUNNING" '.app_was_running=$app' /tmp/task_result.json > /tmp/task_result_final.json
mv /tmp/task_result_final.json /tmp/task_result.json

chmod 666 /tmp/task_result.json
echo "Export complete."
cat /tmp/task_result.json