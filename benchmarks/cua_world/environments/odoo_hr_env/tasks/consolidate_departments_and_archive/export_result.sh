#!/bin/bash
echo "=== Exporting Consolidate Departments Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for the final state
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'
output_file = '/tmp/task_result.json'

result = {
    "source_dept_exists": False,
    "source_dept_active": True,  # Default to true (bad state)
    "source_dept_employee_count": -1,
    "target_employee_found": False,
    "target_employee_dept": "None",
    "target_employee_dept_id": 0,
    "target_dept_id": 0,
    "target_dept_name": "Research & Development"
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check Source Department 'R&D USA' status
    # Search for it regardless of active status
    source_data = models.execute_kw(db, uid, password, 'hr.department', 'search_read',
        [[['name', '=', 'R&D USA'], '|', ['active', '=', True], ['active', '=', False]]],
        {'fields': ['id', 'active']})
    
    if source_data:
        result["source_dept_exists"] = True
        result["source_dept_active"] = source_data[0]['active']
        source_id = source_data[0]['id']
        
        # Check employee count in source department
        count = models.execute_kw(db, uid, password, 'hr.employee', 'search_count',
            [[['department_id', '=', source_id]]])
        result["source_dept_employee_count"] = count
    
    # 2. Check Target Employee 'Robert Miller'
    emp_data = models.execute_kw(db, uid, password, 'hr.employee', 'search_read',
        [[['name', '=', 'Robert Miller']]],
        {'fields': ['department_id']})
    
    if emp_data:
        result["target_employee_found"] = True
        dept_info = emp_data[0]['department_id'] # [id, name] or False
        if dept_info:
            result["target_employee_dept_id"] = dept_info[0]
            result["target_employee_dept"] = dept_info[1]
        else:
            result["target_employee_dept"] = "None"
    
    # 3. Get ID of 'Research & Development' for strict comparison
    target_dept = models.execute_kw(db, uid, password, 'hr.department', 'search_read',
        [[['name', '=', 'Research & Development']]],
        {'fields': ['id']})
    if target_dept:
        result["target_dept_id"] = target_dept[0]['id']

except Exception as e:
    result["error"] = str(e)

# Write result to JSON file
with open(output_file, 'w') as f:
    json.dump(result, f)

print(f"Exported result to {output_file}")
PYTHON_EOF

# Add system-level info to the JSON (using jq or python to merge would be cleaner, 
# but we'll just append fields to the Python dict above to keep it simple)

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="