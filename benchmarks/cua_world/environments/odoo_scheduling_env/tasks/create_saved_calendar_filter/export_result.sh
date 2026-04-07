#!/bin/bash
echo "=== Exporting create_saved_calendar_filter result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query Odoo database for the filter
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import os
import datetime

url = '$ODOO_URL'
db = '$ODOO_DB'
username = '$ODOO_USER'
password = '$ODOO_PASSWORD'

result = {
    "filter_found": False,
    "filter_details": {},
    "grace_patel_id": None,
    "task_timestamp": datetime.datetime.now().isoformat()
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # 1. Get Grace Patel's ID for verification reference
    grace_ids = models.execute_kw(db, uid, password, 'res.partner', 'search',
        [[['name', '=', 'Grace Patel']]])
    if grace_ids:
        result["grace_patel_id"] = grace_ids[0]
        
    # 2. Search for the saved filter
    filter_ids = models.execute_kw(db, uid, password, 'ir.filters', 'search',
        [[['name', '=', 'CFO Schedule'], ['model_id', '=', 'calendar.event']]])
        
    if filter_ids:
        result["filter_found"] = True
        # Read the most recently created one if multiple (though setup clears them)
        filters = models.execute_kw(db, uid, password, 'ir.filters', 'read',
            [filter_ids], {'fields': ['name', 'domain', 'context', 'create_date']})
        
        # Sort by create_date desc to get the one made during task
        filters.sort(key=lambda x: x.get('create_date', ''), reverse=True)
        result["filter_details"] = filters[0]

except Exception as e:
    result["error"] = str(e)

# Write result to JSON file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export logic complete.")
PYTHON_EOF

# Set permissions so verifier can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="