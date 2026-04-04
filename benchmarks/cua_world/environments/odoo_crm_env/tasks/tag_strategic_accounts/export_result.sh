#!/bin/bash
echo "=== Exporting Results: Tag Strategic Accounts ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python script to query Odoo and export results to JSON
python3 - <<'PYEOF'
import xmlrpc.client
import json
import os
import time

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    tag_name = "Strategic Account"
    partners_to_check = ["Logistics Pro Inc", "NorthWest Retail", "SmallTime LLC"]
    
    # Get the ID of the Strategic Account tag
    tag_ids = models.execute_kw(db, uid, password, 'res.partner.category', 'search', [[['name', '=', tag_name]]])
    strategic_tag_id = tag_ids[0] if tag_ids else None
    
    results = {}
    
    if not strategic_tag_id:
        results["error"] = "Tag 'Strategic Account' not found in system"
    else:
        results["tag_id"] = strategic_tag_id
        results["partners"] = {}
        
        for name in partners_to_check:
            p_ids = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', name]]])
            if p_ids:
                pid = p_ids[0]
                # Read specific fields: name, category_id (tags), write_date
                data = models.execute_kw(db, uid, password, 'res.partner', 'read', [pid], {'fields': ['name', 'category_id', 'write_date']})[0]
                
                # Check if strategic tag is in the category_id list
                # category_id returns a list of IDs e.g. [1, 5]
                has_tag = strategic_tag_id in data.get('category_id', [])
                
                results["partners"][name] = {
                    "id": pid,
                    "has_tag": has_tag,
                    "write_date": data.get('write_date')
                }
            else:
                results["partners"][name] = {"error": "Partner not found"}

    # Add timestamp info
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            start_time = int(f.read().strip())
    except:
        start_time = 0
        
    results["task_start_time"] = start_time
    results["export_time"] = int(time.time())

    # Write to JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(results, f, indent=2)
        
    print("Export successful.")

except Exception as e:
    print(f"Error during export: {e}")
    # Write error to JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({"error": str(e)}, f)

PYEOF

# 3. Secure file permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="