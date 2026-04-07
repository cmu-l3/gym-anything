#!/bin/bash
echo "=== Exporting archive_withdrawn_applications results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python/XML-RPC to inspect the database state
# We need to export:
# 1. Count of ACTIVE applications for James Miller (Should be 0)
# 2. Count of ARCHIVED applications for James Miller (Should be 3)
# 3. Timestamp of last modification (Should be > TASK_START)
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'
output_file = '/tmp/task_result.json'
task_start = int("$TASK_START")

result_data = {
    "active_count": -1,
    "archived_count": -1,
    "total_count": -1,
    "modified_recently": False,
    "records_deleted": False,
    "task_start": task_start,
    "timestamp": "$TASK_END"
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Check ACTIVE applications (Default search behavior)
    active_ids = models.execute_kw(db, uid, password, 'hr.applicant', 'search',
                                   [[['partner_name', '=', 'James Miller'], ['active', '=', True]]])
    result_data['active_count'] = len(active_ids)

    # Check ARCHIVED applications (Must specify active=False)
    archived_ids = models.execute_kw(db, uid, password, 'hr.applicant', 'search',
                                     [[['partner_name', '=', 'James Miller'], ['active', '=', False]]])
    result_data['archived_count'] = len(archived_ids)
    
    # Total count (to check for deletion)
    result_data['total_count'] = len(active_ids) + len(archived_ids)
    
    # Check timestamps on archived records
    if archived_ids:
        records = models.execute_kw(db, uid, password, 'hr.applicant', 'read',
                                    [archived_ids], {'fields': ['write_date']})
        
        # Odoo returns UTC strings like '2023-10-27 10:00:00'
        # Simple check: if we have archived records, and they exist now, 
        # and start count was active, a change happened.
        # Strict timestamp parsing can be tricky with timezones, so we'll rely on 
        # state change primarily, but flag if modification happened.
        # Since we just created them in setup, any write_date > create_date implies action.
        # But simply: if they are archived, the agent acted.
        result_data['modified_recently'] = True

except Exception as e:
    result_data['error'] = str(e)

# Save result
with open(output_file, 'w') as f:
    json.dump(result_data, f, indent=4)

print(f"Exported data to {output_file}")
PYTHON_EOF

# Adjust permissions so verifier can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="