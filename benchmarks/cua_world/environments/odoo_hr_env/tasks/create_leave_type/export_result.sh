#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_leave_type result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo database for the result using Python
python3 << EOF > /tmp/task_result.json
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": int("$INITIAL_COUNT"),
    "final_count": 0,
    "found": False,
    "record": {},
    "all_types": []
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Get final count
    result["final_count"] = models.execute_kw(db, uid, password, 'hr.leave.type', 'search_count', [[['active', '=', True]]])

    # Search for the specific record
    # We search case-insensitive to be lenient, but check exact match in verifier
    ids = models.execute_kw(db, uid, password, 'hr.leave.type', 'search',
        [[['name', 'ilike', 'Work From Home']]])
    
    if ids:
        # Get data for the most recently created one (highest ID)
        target_id = max(ids)
        fields = ['name', 'requires_allocation', 'leave_validation_type', 'create_date']
        data = models.execute_kw(db, uid, password, 'hr.leave.type', 'read', [[target_id], fields])
        
        if data:
            result["found"] = True
            result["record"] = data[0]
            
            # Check creation time to ensure it wasn't pre-existing (anti-gaming)
            # Odoo returns strings like '2023-10-25 10:00:00' (UTC)
            # This is a secondary check; the setup script cleaned up, so existence is strong evidence.
    
    # Debug: get list of all names
    all_records = models.execute_kw(db, uid, password, 'hr.leave.type', 'search_read', 
        [[['active', '=', True]]], {'fields': ['name']})
    result["all_types"] = [r['name'] for r in all_records]

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json