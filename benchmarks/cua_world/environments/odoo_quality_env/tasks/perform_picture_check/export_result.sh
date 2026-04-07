#!/bin/bash
echo "=== Exporting perform_picture_check results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final visual state
take_screenshot /tmp/task_final.png

# 2. Python script to query Odoo and export result JSON
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import os

url = '$ODOO_URL'
db = '$ODOO_DB'
username = '$ODOO_USER'
password = '$ODOO_PASSWORD'
task_start_file = '/tmp/task_start_time.txt'

result = {
    "check_found": False,
    "quality_state": "none",
    "picture_size": 0,
    "note_content": "",
    "write_date": "",
    "task_start_ts": 0,
    "check_id": 0
}

# Get task start timestamp
try:
    with open(task_start_file, 'r') as f:
        result["task_start_ts"] = float(f.read().strip())
except:
    pass

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find the check for Office Chair
    # We search for the most recently modified check for this product that is a picture type
    prod_ids = models.execute_kw(db, uid, password, 'product.product', 'search', [[['name', '=', 'Office Chair']]])
    
    if prod_ids:
        pid = prod_ids[0]
        # Find check
        check_ids = models.execute_kw(db, uid, password, 'quality.check', 'search', 
            [[['product_id', '=', pid], ['test_type', '=', 'picture']]],
            {'limit': 1, 'order': 'write_date desc'}
        )
        
        if check_ids:
            check_data = models.execute_kw(db, uid, password, 'quality.check', 'read', 
                [check_ids[0]], ['quality_state', 'picture', 'note', 'write_date'])[0]
            
            result["check_found"] = True
            result["check_id"] = check_ids[0]
            result["quality_state"] = check_data.get('quality_state', 'none')
            result["note_content"] = check_data.get('note') or ""
            result["write_date"] = check_data.get('write_date', "")
            
            # Check picture field (it's base64 string if present, False if not)
            picture_data = check_data.get('picture')
            if picture_data and isinstance(picture_data, str):
                result["picture_size"] = len(picture_data)
            elif picture_data:
                # In case it's bytes or some other truthy value
                result["picture_size"] = 1 
            else:
                result["picture_size"] = 0

except Exception as e:
    result["error"] = str(e)

# Write result to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)

print("Exported result:", json.dumps(result))
PYTHON_EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="