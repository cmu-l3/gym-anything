#!/bin/bash
echo "=== Exporting manage_job_recruitment_lifecycle result ==="

# Source utilities for screenshot
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query database state and export to JSON
python3 << 'PYEOF'
import xmlrpc.client
import json
import os
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'
output_file = '/tmp/task_result.json'

result = {
    "consultant": None,
    "trainee": None,
    "task_start_time": 0,
    "odoo_running": False
}

# Read start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result['task_start_time'] = int(f.read().strip())
except:
    pass

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if uid:
        result['odoo_running'] = True
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

        # Get Consultant Data
        c_ids = models.execute_kw(db, uid, password, 'hr.job', 'search', [[['name', '=', 'Consultant']]])
        if c_ids:
            c_data = models.execute_kw(db, uid, password, 'hr.job', 'read', [c_ids, ['state', 'write_date']])
            if c_data:
                result['consultant'] = c_data[0]

        # Get Trainee Data
        t_ids = models.execute_kw(db, uid, password, 'hr.job', 'search', [[['name', '=', 'Trainee']]])
        if t_ids:
            t_data = models.execute_kw(db, uid, password, 'hr.job', 'read', [t_ids, ['state', 'no_of_recruitment', 'user_id', 'write_date']])
            if t_data:
                result['trainee'] = t_data[0]

except Exception as e:
    print(f"Export Error: {e}", file=sys.stderr)

# Write result to file
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result exported to {output_file}")
PYEOF

# Set permissions so ga user/verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="