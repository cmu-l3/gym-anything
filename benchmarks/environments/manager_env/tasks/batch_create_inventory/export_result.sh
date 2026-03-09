#!/bin/bash
# Export script for batch_create_inventory task
# Fetches final inventory state and compares with initial.

echo "=== Exporting batch_create_inventory result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve Business Key and Initial Count
BIZ_KEY=$(cat /tmp/biz_key.txt 2>/dev/null)
INITIAL_COUNT=$(cat /tmp/initial_inventory_count.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
COOKIE_FILE="/tmp/mgr_cookies.txt"

# 3. Fetch Final Inventory Data
if [ -n "$BIZ_KEY" ]; then
    echo "Fetching final inventory items..."
    curl -s -b "$COOKIE_FILE" "http://localhost:8080/inventory-items?$BIZ_KEY" > /tmp/final_inventory.html
else
    echo "ERROR: Business Key not found."
    echo "<html></html>" > /tmp/final_inventory.html
fi

# 4. Parse Inventory Data into JSON
# We extract Item Name, Code, and Sales Price from the HTML table
python3 -c "
import sys
import json
import re

html = open('/tmp/final_inventory.html').read()
items = []

# Regex to find rows. This is brittle but works for Manager's standard table layout.
# We look for the edit link which usually contains the Item UUID, then cell contents.
# A more robust way in this env is hard without BeautifulSoup, so we try simple text extraction if specific markers exist.

# Let's try to extract relevant text chunks. 
# Manager tables: <td>Code</td><td>Name</td>...<td class='text-right'>Price</td>
# We will just verify existence of our target strings for simplicity and robustness in bash/python-std-lib.

target_items = [
    {'code': 'SEA-001', 'name': 'Hokkaido Garlic Salt', 'price': '15.50'},
    {'code': 'SEA-002', 'name': 'Smoked Paprika Tin', 'price': '9.25'},
    {'code': 'SEA-003', 'name': 'Truffle Infused Oil', 'price': '28.00'}
]

found_items = []
current_count = html.count('<tr>') - 1
if current_count < 0: current_count = 0

# Check for existence of each target item in the HTML
for target in target_items:
    # We check if the specific strings exist. 
    # To be safer, we check if Code and Name appear near each other? 
    # For now, simple existence check of Code AND Name is strong evidence.
    
    found = False
    if target['code'] in html and target['name'] in html:
        # Check price (might be formatted like 15.50 or 15,50)
        if target['price'] in html:
            found = True
    
    if found:
        found_items.append(target)

result = {
    'initial_count': int(sys.argv[1]),
    'final_count': current_count,
    'found_items': found_items,
    'html_snippet_length': len(html)
}

print(json.dumps(result))
" "$INITIAL_COUNT" > /tmp/inventory_analysis.json

# 5. Check if App was Running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 6. Compile Final Result
# Merge the python analysis with standard fields
jq -n \
    --slurpfile analysis /tmp/inventory_analysis.json \
    --arg start "$TASK_START" \
    --arg app_running "$APP_RUNNING" \
    '{
        task_start: $start,
        app_was_running: $app_running,
        inventory_stats: $analysis[0],
        screenshot_path: "/tmp/task_final.png"
    }' > /tmp/task_result.json

# Permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="