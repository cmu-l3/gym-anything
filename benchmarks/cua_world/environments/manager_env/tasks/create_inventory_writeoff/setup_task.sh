#!/bin/bash
set -e

echo "=== Setting up Create Inventory Write-off Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure Manager is running and ready
wait_for_manager 60

# 2. Record Task Start Time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Python script to ensure data requirements:
#    - Northwind business exists
#    - 'Inventory Write-offs' tab is enabled
#    - 'Chai Tea' and 'Aniseed Syrup' items exist
#    - Record initial count of write-offs

cat > /tmp/setup_writeoff_data.py << 'PYEOF'
import requests
import sys
import re
import json

BASE_URL = "http://localhost:8080"
SESSION = requests.Session()

def get_business_key():
    # Login
    SESSION.post(f"{BASE_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    
    # Get Businesses page
    resp = SESSION.get(f"{BASE_URL}/businesses")
    
    # Extract Northwind key
    match = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
    if not match:
        # Try finding just the first business if specific name fails (fallback)
        match = re.search(r'start\?([^"&\s]+)', resp.text)
    
    if match:
        return match.group(1)
    return None

def ensure_tab_enabled(biz_key, tab_name="InventoryWriteOffs"):
    # Get Tabs JSON
    resp = SESSION.get(f"{BASE_URL}/tabs-form?{biz_key}")
    
    # Extract the JSON value from the hidden input or JS
    # Manager puts the state in a value="{...}" attribute
    match = re.search(r'value="({[^"]+})"', resp.text)
    if match:
        current_tabs = json.loads(match.group(1).replace('&quot;', '"'))
        if not current_tabs.get(tab_name):
            print(f"Enabling {tab_name}...")
            current_tabs[tab_name] = True
            
            # Find the fileID/key for the form submission
            # It's usually the name of the input field holding the JSON
            field_match = re.search(r'name="([a-f0-9-]+)" value="{', resp.text)
            if field_match:
                field_name = field_match.group(1)
                SESSION.post(f"{BASE_URL}/tabs-form?{biz_key}", data={field_name: json.dumps(current_tabs)})
                return True
    return False

def ensure_item_exists(biz_key, item_name, sales_price=10.0):
    # Check if item exists in list
    resp = SESSION.get(f"{BASE_URL}/inventory-items?{biz_key}")
    if item_name in resp.text:
        return True
        
    print(f"Creating item: {item_name}")
    # Get form to find field ID
    resp = SESSION.get(f"{BASE_URL}/inventory-item-form?{biz_key}")
    field_match = re.search(r'name="([a-f0-9-]+)"', resp.text)
    if field_match:
        field_name = field_match.group(1)
        # Minimal Item JSON
        item_json = {"ItemName": item_name, "SalesPrice": sales_price, "ItemCode": item_name[:3].upper()}
        SESSION.post(f"{BASE_URL}/inventory-item-form?{biz_key}", data={field_name: json.dumps(item_json)})
        return True
    return False

def get_initial_count(biz_key):
    resp = SESSION.get(f"{BASE_URL}/inventory-write-offs?{biz_key}")
    # Count rows in the table roughly
    count = resp.text.count('<td class="text-start">') // 2  # Approximate
    with open("/tmp/initial_writeoff_count.txt", "w") as f:
        f.write(str(count))
    print(f"Initial count: {count}")

def main():
    key = get_business_key()
    if not key:
        print("Error: Could not find business key")
        sys.exit(1)
        
    ensure_tab_enabled(key, "InventoryWriteOffs")
    ensure_item_exists(key, "Chai Tea", 18.00)
    ensure_item_exists(key, "Aniseed Syrup", 10.00)
    get_initial_count(key)

if __name__ == "__main__":
    main()
PYEOF

python3 /tmp/setup_writeoff_data.py

# 4. Open Firefox to the specific module
# Use the utility to open clean firefox instance
open_manager_at "inventory_write_offs"

# 5. Capture Initial Screenshot
sleep 5 # Wait for browser render
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="