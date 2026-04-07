#!/bin/bash
echo "=== Exporting configure_job_recruitment_settings result ==="

source /workspace/scripts/task_utils.sh

TARGET_JOB_ID=$(cat /tmp/target_job_id.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the SPECIFIC job ID we tracked during setup
# This prevents gaming by creating a duplicate job instead of editing the existing one
python3 << PYTHON_EOF
import xmlrpc.client, json, sys, os

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'
job_id = int("$TARGET_JOB_ID")

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "job_found": False,
    "alias_name": None,
    "recruiter_name": None,
    "target_count": 0,
    "job_id": job_id
}

try:
    if job_id > 0:
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, username, password, {})
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

        # Read specific fields
        fields = ['name', 'alias_name', 'user_id', 'no_of_recruitment']
        data = models.execute_kw(db, uid, password, 'hr.job', 'read', [[job_id], fields])
        
        if data:
            record = data[0]
            result["job_found"] = True
            result["alias_name"] = record.get('alias_name') or ""
            result["target_count"] = record.get('no_of_recruitment') or 0
            
            # user_id is (id, name) tuple in Odoo read results
            user_field = record.get('user_id')
            if user_field and isinstance(user_field, list) and len(user_field) > 1:
                result["recruiter_name"] = user_field[1]
            else:
                result["recruiter_name"] = None
                
except Exception as e:
    result["error"] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported data:")
print(json.dumps(result, indent=2))
PYTHON_EOF

# Set permissions so the host can read it (if mapped volumes have permission issues)
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="