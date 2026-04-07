#!/bin/bash
echo "=== Exporting Hire Job Applicant results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_EMP_COUNT=$(cat /tmp/initial_employee_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to query Odoo state and export to JSON
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

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_employee_count": int("$INITIAL_EMP_COUNT"),
    "final_employee_count": 0,
    "applicant_found": False,
    "applicant_stage_name": None,
    "applicant_is_hired_stage": False,
    "applicant_linked_emp_id": False,
    "employee_found": False,
    "employee_name": None,
    "employee_job_title": None,
    "employee_create_date": None,
    "error": None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check Employee Count
    result["final_employee_count"] = models.execute_kw(db, uid, password, 'hr.employee', 'search_count', [[]])

    # 2. Inspect Applicant "Sofia Martinez"
    app_ids = models.execute_kw(db, uid, password, 'hr.applicant', 'search',
                                [[['partner_name', '=', 'Sofia Martinez']]])
    
    if app_ids:
        result["applicant_found"] = True
        app_data = models.execute_kw(db, uid, password, 'hr.applicant', 'read',
                                     [app_ids[0]], {'fields': ['stage_id', 'emp_id']})
        if app_data:
            data = app_data[0]
            # stage_id is (id, name)
            if data.get('stage_id'):
                stage_id = data['stage_id'][0]
                stage_name = data['stage_id'][1]
                result["applicant_stage_name"] = stage_name
                
                # Check if this stage is a "hired" stage (folded in kanban usually means done, 
                # or specific boolean 'hired_stage' if module extension exists, 
                # but standard check is usually "Contract Signed")
                stage_info = models.execute_kw(db, uid, password, 'hr.recruitment.stage', 'read',
                                               [stage_id], {'fields': ['name', 'fold', 'sequence']})
                # In standard Odoo recruitment, "Contract Signed" is the final stage
                if "Contract Signed" in stage_name or "Hired" in stage_name:
                    result["applicant_is_hired_stage"] = True

            # Check linked employee
            # emp_id is (id, name) or False
            if data.get('emp_id'):
                result["applicant_linked_emp_id"] = data['emp_id'][0]

    # 3. Inspect Employee "Sofia Martinez"
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search',
                                [[['name', '=', 'Sofia Martinez']]])
    
    if emp_ids:
        result["employee_found"] = True
        emp_data = models.execute_kw(db, uid, password, 'hr.employee', 'read',
                                     [emp_ids[0]], {'fields': ['name', 'job_id', 'create_date']})
        if emp_data:
            data = emp_data[0]
            result["employee_name"] = data.get('name')
            result["employee_create_date"] = data.get('create_date')
            if data.get('job_id'):
                result["employee_job_title"] = data['job_id'][1]

except Exception as e:
    result["error"] = str(e)

# Write result to JSON
with open(output_file, 'w') as f:
    json.dump(result, f, indent=4)

print("Export complete.")
PYTHON_EOF

# Set permissions so ga user can read it if needed, though export runs as root usually
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Content of result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="