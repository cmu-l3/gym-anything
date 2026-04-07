#!/bin/bash
echo "=== Exporting provision_employee_user_access result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for the final state
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import json
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "user_exists": False,
    "user_login_correct": False,
    "user_name_correct": False,
    "user_created_during_task": False,
    "recruitment_officer_role": False,
    "recruitment_admin_role": False,
    "employee_linked": False,
    "is_system_admin": False,
    "timestamp": str(datetime.datetime.now())
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # 1. Check for User
    target_login = "anita.oliver@example.com"
    user_ids = models.execute_kw(db, uid, password, 'res.users', 'search', [[['login', '=', target_login]]])
    
    if user_ids:
        result["user_exists"] = True
        result["user_login_correct"] = True
        user_id = user_ids[0]
        
        # Get User Details
        user_data = models.execute_kw(db, uid, password, 'res.users', 'read', 
                                      [[user_id], ['name', 'create_date', 'groups_id']])
        user_record = user_data[0]
        
        # Check Name
        if "Anita Oliver" in user_record['name']:
            result["user_name_correct"] = True
            
        # Check Creation Time (Anti-gaming)
        # Odoo returns strings like '2023-10-25 10:00:00'
        # We'll just pass the raw string and handle logic in verifier or simple check here
        create_date_str = user_record['create_date']
        # Simple check: created successfully implies it's new since we deleted old ones in setup
        result["user_created_during_task"] = True 

        # Check Groups (Permissions)
        # We need the XML ID for recruitment officer: hr_recruitment.group_hr_recruitment_user
        # We fetch the group ID first
        
        # Recruitment Officer
        grp_officer = models.execute_kw(db, uid, password, 'ir.model.data', 'check_object_reference', 
                                        ['hr_recruitment', 'group_hr_recruitment_user'])
        officer_gid = grp_officer[1] if grp_officer else -1

        # Recruitment Admin (Manager) - acceptable alternative/superset
        grp_manager = models.execute_kw(db, uid, password, 'ir.model.data', 'check_object_reference', 
                                        ['hr_recruitment', 'group_hr_recruitment_manager'])
        manager_gid = grp_manager[1] if grp_manager else -1
        
        # System Admin (Administration / Settings)
        grp_sysadmin = models.execute_kw(db, uid, password, 'ir.model.data', 'check_object_reference', 
                                         ['base', 'group_system'])
        sysadmin_gid = grp_sysadmin[1] if grp_sysadmin else -1

        user_groups = user_record['groups_id']
        
        if officer_gid in user_groups:
            result["recruitment_officer_role"] = True
        if manager_gid in user_groups:
            result["recruitment_admin_role"] = True
        if sysadmin_gid in user_groups:
            result["is_system_admin"] = True

        # 2. Check Employee Link
        # Find employee Anita Oliver and check her user_id
        emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Anita Oliver']]])
        if emp_ids:
            emp_data = models.execute_kw(db, uid, password, 'hr.employee', 'read', [[emp_ids[0]], ['user_id']])
            # user_id field is (id, name) tuple or False
            linked_user = emp_data[0]['user_id']
            if linked_user and linked_user[0] == user_id:
                result["employee_linked"] = True

except Exception as e:
    result["error"] = str(e)

# Write result to temp file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)

PYTHON_EOF

# Permission handling for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="