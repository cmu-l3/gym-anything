#!/bin/bash
# Export script for record_partial_goods_receipt task
# Extracts Goods Receipts from Manager.io for verification

set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Goods Receipts data using Python
#    We fetch the Goods Receipts list and details
cat > /tmp/export_data.py << 'PYEOF'
import requests
import re
import json
import sys

MANAGER_URL = "http://localhost:8080"

def get_session():
    s = requests.Session()
    s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    return s

def get_business_key(s):
    r = s.get(f"{MANAGER_URL}/businesses")
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', r.text)
    return m.group(1) if m else None

def get_uuid_from_link(link):
    m = re.search(r'Key=([a-f0-9-]+)', link)
    return m.group(1) if m else None

def main():
    s = get_session()
    biz_key = get_business_key(s)
    if not biz_key:
        print(json.dumps({"error": "Business not found"}))
        return

    # 1. Get List of Goods Receipts
    r = s.get(f"{MANAGER_URL}/goods-receipts?{biz_key}")
    html = r.text
    
    # We look for links to view/edit goods receipts to get their IDs
    # Pattern: <a href="goods-receipt-view?Key=...">View</a>
    # We collect all UUIDs found on the page
    receipt_ids = re.findall(r'goods-receipt-view\?Key=([a-f0-9-]+)', html)
    
    receipts_data = []
    
    # 2. Fetch details for each receipt
    # Note: Manager doesn't have a clean JSON API for "GET /goods-receipts/ID" that returns pure JSON easily
    # accessible without knowing the exact internal field names which change.
    # However, the "Edit" form usually contains the JSON in the hidden input.
    # Let's try to fetch the Edit form (goods-receipt-form?Key=...)
    
    for rid in list(set(receipt_ids)):
        r_form = s.get(f"{MANAGER_URL}/goods-receipt-form?Key={rid}&{biz_key}")
        # Extract the JSON payload from the hidden input value
        # value="{&quot;IssueDate&quot;:...}"
        m = re.search(r'value="(\{.*?\})"', r_form.text)
        if m:
            try:
                # The value is HTML escaped (e.g. &quot;)
                raw_json = m.group(1).replace('&quot;', '"').replace('&amp;', '&')
                data = json.loads(raw_json)
                data['_id'] = rid
                receipts_data.append(data)
            except Exception as e:
                pass
    
    # Also fetch Item names mapping if possible, or just export raw UUIDs
    # We'll resolve UUIDs in the verifier if needed, or fetch map here
    # Fetching Inventory Items to map UUID -> Name
    items_map = {}
    r_items = s.get(f"{MANAGER_URL}/inventory-items?{biz_key}")
    # This is hard to parse reliably from HTML table without bs4
    # But we can try to find the items we care about in the receipts
    
    # Helper to resolve Item UUID to Name by visiting the item form? Too slow.
    # We will assume the verifier knows the UUID from setup or we export the raw IDs.
    # Actually, let's try to get the item list JSON if manager supports .json suffix
    
    print(json.dumps({
        "goods_receipts": receipts_data,
        "business_key": biz_key
    }))

if __name__ == "__main__":
    main()
PYEOF

# Run export script
python3 /tmp/export_data.py > /tmp/manager_data.json 2>/dev/null || echo "{}" > /tmp/manager_data.json

# 3. Gather final metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then SCREENSHOT_EXISTS="true"; fi

# 4. Construct result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "manager_data": $(cat /tmp/manager_data.json)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"