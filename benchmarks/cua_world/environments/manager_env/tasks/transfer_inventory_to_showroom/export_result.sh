#!/bin/bash
echo "=== Exporting Transfer Inventory Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------------------
# Extract Data from Manager.io via Python
# ---------------------------------------------------------------------------
echo "Extracting data from Manager.io..."

PYTHON_EXPORT_SCRIPT=$(cat << 'EOF'
import requests
import re
import sys
import json
import time

MANAGER_URL = "http://localhost:8080"
s = requests.Session()

result = {
    "modules_enabled": [],
    "locations": [],
    "transfers": [],
    "inventory_items": {}
}

try:
    # Login
    s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)

    # Get Business Key
    resp = s.get(f"{MANAGER_URL}/businesses")
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
    if m:
        biz_key = m.group(1)
        
        # 1. Check Enabled Modules (by parsing sidebar on Summary page)
        summary_resp = s.get(f"{MANAGER_URL}/summary?{biz_key}")
        sidebar_text = summary_resp.text
        
        if "Inventory Locations" in sidebar_text or "inventory-locations?" in sidebar_text:
            result["modules_enabled"].append("InventoryLocations")
        if "Inventory Transfers" in sidebar_text or "inventory-transfers?" in sidebar_text:
            result["modules_enabled"].append("InventoryTransfers")
            
        # 2. Get Locations
        # Attempt to access locations page
        loc_resp = s.get(f"{MANAGER_URL}/inventory-locations?{biz_key}")
        if loc_resp.status_code == 200:
            # Simple scrape: Look for table rows. 
            # This is fragile but standard for this env without direct DB access.
            # We look for "Showroom" in the text
            if "Showroom" in loc_resp.text:
                result["locations"].append({"name": "Showroom"})
                
        # 3. Get Transfers
        # Access transfers list
        trans_resp = s.get(f"{MANAGER_URL}/inventory-transfers?{biz_key}")
        if trans_resp.status_code == 200:
            # Look for date 2026-05-01
            if "01/05/2026" in trans_resp.text or "2026-05-01" in trans_resp.text or "May 1, 2026" in trans_resp.text:
                 # We need deeper verification. Let's try to parse the edit link to get details.
                 # Find edit link for the latest transfer
                 edit_links = re.findall(r'href="(inventory-transfer-form\?[^"]+)"', trans_resp.text)
                 for link in edit_links:
                     detail_url = f"{MANAGER_URL}/{link}"
                     detail_resp = s.get(detail_url)
                     
                     # Extract fields from form values
                     transfer_data = {}
                     
                     # Date
                     date_m = re.search(r'name="[^"]*Date[^"]*" value="([^"]+)"', detail_resp.text)
                     if date_m: transfer_data["date"] = date_m.group(1)
                     
                     # Description
                     desc_m = re.search(r'name="[^"]*Description[^"]*"[^>]*>([^<]*)<', detail_resp.text)
                     if desc_m: 
                        transfer_data["description"] = desc_m.group(1)
                     else:
                        # Try input value style
                        desc_m2 = re.search(r'name="[^"]*Description[^"]*" value="([^"]+)"', detail_resp.text)
                        if desc_m2: transfer_data["description"] = desc_m2.group(1)
                        
                     # Lines - looking for Chai UUID or text
                     # We might find "Chai" in the selected option or javascript data
                     if "Chai" in detail_resp.text:
                         transfer_data["item_name"] = "Chai"
                         
                     # Quantity - look for "40" in inputs
                     if 'value="40"' in detail_resp.text or 'value="40.0"' in detail_resp.text:
                         transfer_data["qty"] = 40
                     
                     result["transfers"].append(transfer_data)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF
)

# Run Python script and save result
python3 -c "$PYTHON_EXPORT_SCRIPT" > /tmp/raw_data.json

# Merge with file info
cat > /tmp/export_helper.py << 'EOF'
import json
import os
import sys

try:
    with open('/tmp/raw_data.json', 'r') as f:
        data = json.load(f)
except:
    data = {"error": "Failed to load raw data"}

task_start = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except:
    pass

final_result = {
    "task_start": task_start,
    "timestamp": time.time(),
    "manager_data": data,
    "screenshot_exists": os.path.exists("/tmp/task_final.png")
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_result, f, indent=2)
EOF

python3 /tmp/export_helper.py

# Cleanup
rm -f /tmp/raw_data.json /tmp/export_helper.py

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="