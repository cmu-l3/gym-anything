#!/bin/bash
echo "=== Exporting create_job_application results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve setup data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_id.txt 2>/dev/null || echo "0")

# Query Odoo for the result using Python/XML-RPC
# We do the heavy verification logic inside the container where we have access to the DB API
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
output_file = '/tmp/task_result.json'

result = {
    "found": False,
    "fields": {},
    "is_new": False,
    "timestamp": str(datetime.datetime.now())
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Search for the applicant
    # We look for "Maria Chen"
    applicant_ids = models.execute_kw(db, uid, 'admin', 'hr.applicant', 'search',
                                     [[['partner_name', 'ilike', 'Maria Chen']]])
    
    if applicant_ids:
        # Get the most recent one if multiple (though setup should have cleared them)
        applicant_id = max(applicant_ids)
        
        # Read fields
        data = models.execute_kw(db, uid, 'admin', 'hr.applicant', 'read',
                                [[applicant_id]],
                                {'fields': ['partner_name', 'email_from', 'partner_phone', 
                                           'salary_expected', 'job_id', 'department_id', 
                                           'create_date']})
        
        if data:
            record = data[0]
            
            # Process relation fields (they return [id, name])
            job_name = record['job_id'][1] if record['job_id'] else ""
            dept_name = record['department_id'][1] if record['department_id'] else ""
            
            result["found"] = True
            result["id"] = applicant_id
            
            # Anti-gaming: Check if ID is greater than what existed at start
            initial_max = int('$INITIAL_MAX_ID')
            result["is_new"] = applicant_id > initial_max
            
            result["fields"] = {
                "name": record.get('partner_name', ''),
                "email": record.get('email_from', ''),
                "phone": record.get('partner_phone', ''),
                "salary": record.get('salary_expected', 0.0),
                "job": job_name,
                "department": dept_name
            }
            
            print(f"Found applicant: {result['fields']}")
    else:
        print("No applicant found with name 'Maria Chen'")

except Exception as e:
    result["error"] = str(e)
    print(f"Error querying Odoo: {e}", file=sys.stderr)

# Save result to JSON
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result saved to {output_file}")
PYTHON_EOF

# Set permissions so host can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="