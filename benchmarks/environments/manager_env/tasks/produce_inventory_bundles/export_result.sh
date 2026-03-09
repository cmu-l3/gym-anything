#!/bin/bash
# Export script for produce_inventory_bundles task
# Scrapes Manager.io state to verify the task outcome.

echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Python script to extract verification data
cat > /tmp/extract_data.py << 'EOF'
import requests
import re
import json
import sys
import time

BASE_URL = "http://localhost:8080"
S = requests.Session()

result = {
    "module_enabled": False,
    "item_created": False,
    "item_details": {},
    "order_created": False,
    "order_details": {}
}

def clean_html(text):
    """Simple cleanup of HTML tags for value extraction."""
    text = re.sub(r'<[^>]+>', '', text)
    return text.strip()

def extract_val(html, label):
    """Heuristic to find value after a label in form view."""
    # Look for label pattern
    # This is rough HTML parsing; Manager.io structure varies but usually follows label -> div/td value
    # We'll try to find the label, then grab the next bit of text
    try:
        # Regex to find the label and subsequent text
        # Manager usually puts label in dt or td, value in dd or td
        pattern = re.compile(rf"{label}.*?</div>.*?<div[^>]*>(.*?)</div>", re.DOTALL | re.IGNORECASE) 
        # Note: This regex is very generic, might need adjustment based on specific DOM
        # Better approach for list views is often table parsing
        pass
    except:
        pass
    return ""

def run():
    # 1. Login
    S.post(f"{BASE_URL}/login", data={"Username": "administrator"}, timeout=10)
    
    # 2. Get Business Key
    resp = S.get(f"{BASE_URL}/businesses", timeout=10)
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', resp.text)
    if not m:
        print("Could not find business")
        return
    key = m.group(1)
    
    # 3. Check if Production Orders module is enabled
    # We check the Summary page or the sidebar for the link
    summary_resp = S.get(f"{BASE_URL}/start?{key}", timeout=10)
    if "production-orders?" in summary_resp.text:
        result["module_enabled"] = True
    
    # 4. Check Inventory Item
    inv_resp = S.get(f"{BASE_URL}/inventory-items?{key}", timeout=10)
    if "BUNDLE-2025" in inv_resp.text or "Beverage Bundle" in inv_resp.text:
        result["item_created"] = True
        # Try to extract details if possible, but existence is the main check here
        # To be precise, we'd need to find the edit link
        m_item = re.search(r'href="([^"]+)">[^<]*BUNDLE-2025', inv_resp.text)
        if m_item:
            item_url = m_item.group(1)
            # Visit item page to confirm details? Not strictly necessary if code matches.
            result["item_details"]["code"] = "BUNDLE-2025"
    
    # 5. Check Production Order
    # Only if module is enabled
    if result["module_enabled"]:
        po_resp = S.get(f"{BASE_URL}/production-orders?{key}", timeout=10)
        
        # Look for the most recent production order
        # We look for a View or Edit link. 
        # Regex for row: usually contains date, reference, description
        # We'll just look for the first link to a production order view/edit
        m_po = re.search(r'href="([^"]+(?:view|edit)-production-order[^"]+)"', po_resp.text)
        
        if m_po:
            result["order_created"] = True
            po_url = m_po.group(1)
            # Normalize URL
            if po_url.startswith("/"):
                po_url = BASE_URL + po_url
            else:
                po_url = BASE_URL + "/" + po_url
                
            po_detail_resp = S.get(po_url, timeout=10)
            html = po_detail_resp.text
            
            # Extract Finished Item (Output)
            # Usually in a table or distinct section
            # We look for "Beverage Bundle" and the quantity associated
            # This is tricky with regex on raw HTML. We'll look for proximity.
            
            # Check for Finished Item name
            if "Beverage Bundle" in html:
                result["order_details"]["finished_item"] = "Beverage Bundle"
            
            # Check for Output Quantity
            # Often near the item name
            # Heuristic: look for number 10 surrounded by tags near Beverage Bundle
            if re.search(r'Beverage Bundle.*?10', html, re.DOTALL):
                 result["order_details"]["finished_qty"] = 10
            
            # Check for Bill of Materials (Inputs)
            inputs = []
            if "Chai" in html and re.search(r'Chai.*?10', html, re.DOTALL):
                inputs.append({"name": "Chai", "qty": 10})
            if "Chang" in html and re.search(r'Chang.*?10', html, re.DOTALL):
                inputs.append({"name": "Chang", "qty": 10})
            
            result["order_details"]["inputs"] = inputs

try:
    run()
except Exception as e:
    result["error"] = str(e)

with open("/tmp/task_result_data.json", "w") as f:
    json.dump(result, f)
EOF

# Run extraction
python3 /tmp/extract_data.py

# Combine with other metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_BUNDLE_EXISTS=$(cat /tmp/initial_bundle_exists.txt 2>/dev/null || echo "false")

# Create final result JSON
python3 -c "
import json
import os

try:
    with open('/tmp/task_result_data.json') as f:
        data = json.load(f)
except:
    data = {}

final = {
    'task_start': $TASK_START,
    'initial_bundle_exists': '$INITIAL_BUNDLE_EXISTS' == 'true',
    'screenshot_path': '/tmp/task_final.png',
    'manager_data': data
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final, f)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="