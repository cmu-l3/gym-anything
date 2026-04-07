#!/bin/bash
echo "=== Exporting clone_job_position results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to query final state
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "task_start_timestamp": int("$TASK_START"),
    "job_found": False,
    "job_details": {},
    "source_job_exists": False,
    "total_jobs": 0
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Check Total Job Count
    result["total_jobs"] = models.execute_kw(db, uid, password, 'hr.job', 'search_count', [[]])

    # Check Source Job (should still exist)
    source_ids = models.execute_kw(db, uid, password, 'hr.job', 'search', [[['name', '=', 'Experienced Developer']]])
    result["source_job_exists"] = bool(source_ids)

    # Check Target Job
    target_ids = models.execute_kw(db, uid, password, 'hr.job', 'search', [[['name', '=', 'Senior Python Developer']]])
    
    if target_ids:
        result["job_found"] = True
        # Read fields: department_id, no_of_recruitment, description, create_date
        fields = ['name', 'department_id', 'no_of_recruitment', 'description', 'create_date']
        data = models.execute_kw(db, uid, password, 'hr.job', 'read', [target_ids, fields])
        
        if data:
            job = data[0]
            # Handle department_id (returns [id, name] or False)
            dept_name = False
            if job.get('department_id'):
                dept_name = job['department_id'][1]
            
            # Normalize create_date to timestamp if possible, or string
            create_date = job.get('create_date', '')
            
            result["job_details"] = {
                "name": job.get('name'),
                "department": dept_name,
                "recruitment_target": job.get('no_of_recruitment'),
                "description_length": len(job.get('description') or ""),
                "create_date": create_date
            }

except Exception as e:
    result["error"] = str(e)
    print(f"Export Error: {e}", file=sys.stderr)

# Write result to temp file
with open('/tmp/result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)

PYTHON_EOF

# Move result to final location with permissions
mv /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json