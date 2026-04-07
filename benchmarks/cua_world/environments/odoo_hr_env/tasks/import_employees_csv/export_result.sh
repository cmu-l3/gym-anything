#!/bin/bash
echo "=== Exporting import_employees_csv results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export results using Python/XMLRPC
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import os
import sys
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "odoo_accessible": False,
    "initial_count": 0,
    "final_count": 0,
    "imported_employees": [],
    "errors": []
}

# Read initial count
try:
    with open('/tmp/initial_employee_count.txt', 'r') as f:
        result["initial_count"] = int(f.read().strip())
except:
    pass

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    
    if uid:
        result["odoo_accessible"] = True
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
        
        # Get final count
        result["final_count"] = models.execute_kw(db, uid, password, 'hr.employee', 'search_count', [[]])
        
        # Check for specific employees
        # We look for the emails defined in the task
        target_emails = [
            "sandra.mitchell@yourcompany.com",
            "kevin.torres@yourcompany.com",
            "laura.chen@yourcompany.com",
            "marcus.johnson@yourcompany.com",
            "diana.ramirez@yourcompany.com"
        ]
        
        # Fetch details for these employees
        # We search by email to identify them uniquely
        emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search',
            [[['work_email', 'in', target_emails]]])
            
        if emp_ids:
            fields = ['name', 'work_email', 'work_phone', 'department_id', 'job_title', 'create_date']
            employees = models.execute_kw(db, uid, password, 'hr.employee', 'read', [emp_ids], {'fields': fields})
            
            for emp in employees:
                # Resolve department name (read returns [id, name])
                dept_name = emp['department_id'][1] if emp['department_id'] else None
                
                result["imported_employees"].append({
                    "name": emp['name'],
                    "email": emp['work_email'],
                    "phone": emp['work_phone'],
                    "department": dept_name,
                    "job_title": emp['job_title'],
                    "create_date": emp['create_date']
                })
    else:
        result["errors"].append("Authentication failed")

except Exception as e:
    result["errors"].append(str(e))

# Save to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYTHON_EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export finished ==="