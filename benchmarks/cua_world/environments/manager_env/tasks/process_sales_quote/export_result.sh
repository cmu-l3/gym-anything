#!/bin/bash
echo "=== Exporting process_sales_quote result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather data
MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_cookies.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_so_count.txt 2>/dev/null || echo "0")

# Login (refresh session)
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# Get Business Key
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(echo "$BIZ_PAGE" | grep -o 'start?[^"]*' | grep "Northwind" | head -1 | cut -d? -f2)
if [ -z "$BIZ_KEY" ]; then
    BIZ_KEY=$(echo "$BIZ_PAGE" | grep -o 'start?[^"]*' | head -1 | cut -d? -f2)
fi

# 3. Analyze Sales Orders
# We need to find a Sales Order created *after* task start (or just the latest one)
# for "Ernst Handel" with "Steeleye Stout".

# Fetch Sales Orders list
SO_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/sales-orders?$BIZ_KEY" -L)
FINAL_COUNT=$(echo "$SO_PAGE" | grep -c "sales-order-view" || echo 0)

# Python script to parse the HTML and find the relevant order details
python3 -c "
import sys
import re
import json
import requests

manager_url = '$MANAGER_URL'
biz_key = '$BIZ_KEY'
cookie_file = '$COOKIE_FILE'
target_customer = 'Ernst Handel'

# Read cookies
cookies = {}
with open(cookie_file, 'r') as f:
    for line in f:
        if not line.startswith('#') and len(line.strip()) > 0:
            parts = line.strip().split()
            if len(parts) >= 7:
                cookies[parts[5]] = parts[6]

session = requests.Session()
for k, v in cookies.items():
    session.cookies.set(k, v)

# Fetch list page again
try:
    resp = session.get(f'{manager_url}/sales-orders?{biz_key}')
    html = resp.text
except Exception as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(0)

# Find all links to sales-order-view
# Regex for row containing customer and link
# Pattern: <td ...>DATE</td> ... <td ...>Ernst Handel</td> ... href=\"(sales-order-view?Key=...)\"
# This is tricky with regex on raw HTML.
# We will look for the view link, then fetch the view and check details.
view_links = re.findall(r'sales-order-view\?Key=[^\"]*', html)

found_orders = []

for link in view_links:
    try:
        order_url = f'{manager_url}/{link}'
        r = session.get(order_url)
        detail_html = r.text
        
        # Check Customer
        if target_customer not in detail_html:
            continue
            
        # Extract Items and Quantities
        # Look for table rows in the content
        # Simple regex for quantity near 'Steeleye Stout'
        # This is a heuristic: look for text 'Steeleye Stout' then shortly after a number
        # Better: parse visual text
        
        # Extract Notes/Description
        # Look for 'Customer confirmed via email'
        has_note = 'confirmed via email' in detail_html.lower()
        
        # Extract Quantity for Steeleye Stout
        # We assume the layout: <td>Steeleye Stout</td>...<td...>24</td>
        # Let's clean tags and look for sequence
        clean_text = re.sub(r'<[^>]+>', ' ', detail_html)
        clean_text = re.sub(r'\s+', ' ', clean_text)
        
        qty = 0
        if 'Steeleye Stout' in clean_text:
            # Try to find the quantity following the item name
            # Usually Item Name -> Account -> Qty -> Price
            # We will just look for '24' in the vicinity if we can't be precise,
            # or rely on the verifier to trust the regex finds it.
            # Let's try to be specific: find 'Steeleye Stout' index, then look for numbers after it
            idx = clean_text.find('Steeleye Stout')
            chunk = clean_text[idx:idx+200]
            # Find numbers in chunk
            nums = re.findall(r' \d+ ', chunk)
            # The quantity is likely one of these. 24 is specific enough.
            if ' 24 ' in chunk:
                qty = 24
            elif ' 20 ' in chunk:
                qty = 20
        
        found_orders.append({
            'url': order_url,
            'customer': target_customer,
            'qty_stout': qty,
            'has_note': has_note,
            'raw_text_snippet': clean_text[:500] # Debug
        })
        
    except:
        continue

# Select best match (preference for Qty=24)
best_match = None
for o in found_orders:
    if o['qty_stout'] == 24:
        best_match = o
        break
if not best_match and found_orders:
    best_match = found_orders[0]

result = {
    'initial_count': $INITIAL_COUNT,
    'final_count': $FINAL_COUNT,
    'order_found': bool(best_match),
    'order_data': best_match if best_match else {},
    'timestamp': $TASK_START
}

print(json.dumps(result))
" > /tmp/parsed_result.json

# Save to final location
rm -f /tmp/task_result.json
cp /tmp/parsed_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json