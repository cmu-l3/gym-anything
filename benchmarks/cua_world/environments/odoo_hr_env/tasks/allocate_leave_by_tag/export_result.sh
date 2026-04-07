#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting allocate_leave_by_tag results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data via Python XML-RPC
# We export relevant allocations created AFTER the task start time.
# We explicitly look for the correct properties to help the verifier.

python3 << PYTHON_EOF
import xmlrpc.client
import json
import time
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'
output_file = '/tmp/task_result.json'

try:
    # Read task start time
    start_time_unix = 0
    if os.path.exists('/tmp/task_start_time.txt'):
        with open('/tmp/task_start_time.txt', 'r') as f:
            start_time_unix = float(f.read().strip())

    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # Fetch all allocations
    # We fetch ALL recent allocations to check for both correct implementation (By Tag)
    # and incorrect implementation (By Employee - gaming/inefficient).
    
    # Odoo dates are strings, so we fetch generic recent ones and filter in Python or just fetch all
    # Since this is a test env, volume is low.
    
    fields = ['name', 'holiday_status_id', 'number_of_days', 'state', 'holiday_type', 'category_id', 'employee_id', 'create_date']
    ids = models.execute_kw(db, uid, password, 'hr.leave.allocation', 'search', [[]])
    allocations = models.execute_kw(db, uid, password, 'hr.leave.allocation', 'read', [ids], {'fields': fields})
    
    # Get names for IDs to make verification easier
    # Helper to get name from (id, name) tuple
    def get_name(field_val):
        return field_val[1] if field_val else None

    results = []
    
    for alloc in allocations:
        # Basic create_date check (approximate, since Odoo might use UTC strings)
        # We'll include everything and let verifier filter strict timestamps if needed,
        # but primarily we rely on the clean state + short task duration.
        
        entry = {
            'id': alloc['id'],
            'name': alloc['name'],
            'days': alloc['number_of_days'],
            'state': alloc['state'],
            'mode': alloc['holiday_type'], # 'category', 'employee', 'company', 'department'
            'leave_type': get_name(alloc['holiday_status_id']),
            'category_name': get_name(alloc['category_id']),
            'employee_name': get_name(alloc['employee_id']),
            'create_date': alloc['create_date']
        }
        results.append(entry)

    export_data = {
        'allocations': results,
        'task_start_timestamp': start_time_unix,
        'screenshot_exists': os.path.exists('/tmp/task_final.png')
    }

    with open(output_file, 'w') as f:
        json.dump(export_data, f, indent=2)

    print(f"Exported {len(results)} allocations to {output_file}")

except Exception as e:
    print(f"Export Error: {e}", file=sys.stderr)
    # Write error json
    with open(output_file, 'w') as f:
        json.dump({'error': str(e)}, f)

PYTHON_EOF

# Set permissions so ga user/verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="