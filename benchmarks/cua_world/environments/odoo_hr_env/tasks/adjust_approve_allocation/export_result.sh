#!/bin/bash
echo "=== Exporting adjust_approve_allocation results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract result using Python
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'
output_file = '/tmp/task_result.json'

result_data = {
    "allocation_found": False,
    "final_state": "unknown",
    "final_days": 0.0,
    "write_date": "",
    "task_start_ts": 0
}

try:
    # Get task start time
    if os.path.exists('/tmp/task_start_time.txt'):
        with open('/tmp/task_start_time.txt', 'r') as f:
            result_data['task_start_ts'] = int(f.read().strip())

    # Get target allocation ID
    if not os.path.exists('/tmp/target_allocation_id.txt'):
        print("Target allocation ID not found", file=sys.stderr)
    else:
        with open('/tmp/target_allocation_id.txt', 'r') as f:
            alloc_id = int(f.read().strip())

        # Connect to Odoo
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, username, password, {})
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

        # Read fields
        data = models.execute_kw(db, uid, password, 'hr.leave.allocation', 'read',
                                 [[alloc_id]], {'fields': ['state', 'number_of_days', 'write_date']})
        
        if data:
            record = data[0]
            result_data["allocation_found"] = True
            result_data["final_state"] = record.get('state')
            result_data["final_days"] = record.get('number_of_days')
            result_data["write_date"] = record.get('write_date')
            print(f"Allocation {alloc_id}: State={record.get('state')}, Days={record.get('number_of_days')}")
        else:
            print(f"Allocation {alloc_id} deleted or not found")

except Exception as e:
    print(f"Export error: {e}", file=sys.stderr)
    result_data["error"] = str(e)

# Write result
with open(output_file, 'w') as f:
    json.dump(result_data, f, indent=2)
PYTHON_EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="