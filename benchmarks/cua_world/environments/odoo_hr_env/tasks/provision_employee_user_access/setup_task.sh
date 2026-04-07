#!/bin/bash
set -e
echo "=== Setting up provision_employee_user_access task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# -------------------------------------------------------
# XML-RPC Setup: Clean slate for Anita Oliver
# 1. Ensure Employee exists (create if missing, though she is in demo data)
# 2. Remove any existing User linked to her
# 3. Remove any User with the target login "anita.oliver@example.com"
# -------------------------------------------------------
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("Auth failed", file=sys.stderr)
        sys.exit(1)
        
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # 1. Find Employee
    emp_name = "Anita Oliver"
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', emp_name]]])
    
    if not emp_ids:
        print(f"Employee {emp_name} not found, creating placeholder...")
        emp_id = models.execute_kw(db, uid, password, 'hr.employee', 'create', [{'name': emp_name}])
    else:
        emp_id = emp_ids[0]
        
    # 2. Unlink any existing user from this employee
    # We read the employee to see if user_id is set
    emp_data = models.execute_kw(db, uid, password, 'hr.employee', 'read', [[emp_id], ['user_id']])
    if emp_data and emp_data[0]['user_id']:
        current_user_id = emp_data[0]['user_id'][0]
        print(f"Unlinking existing user {current_user_id} from {emp_name}")
        models.execute_kw(db, uid, password, 'hr.employee', 'write', [[emp_id], {'user_id': False}])

    # 3. Delete any user with the target login or name to ensure clean creation
    target_login = "anita.oliver@example.com"
    user_ids = models.execute_kw(db, uid, password, 'res.users', 'search', 
                                 ['|', ['login', '=', target_login], ['name', '=', emp_name]])
    
    if user_ids:
        print(f"Removing {len(user_ids)} conflicting user(s)...")
        # In Odoo, deleting users can be tricky due to foreign keys. 
        # We'll try to deactivate and rename login if delete fails, or just delete if clean.
        try:
            models.execute_kw(db, uid, password, 'res.users', 'unlink', [user_ids])
            print("Users deleted.")
        except Exception as e:
            print(f"Could not delete users (likely linked data), deactivating instead: {e}")
            # Rename login to free it up
            for i, uid_to_mod in enumerate(user_ids):
                models.execute_kw(db, uid, password, 'res.users', 'write', 
                                  [[uid_to_mod], {
                                      'active': False, 
                                      'login': f"{target_login}_archived_{i}",
                                      'name': f"{emp_name} (Archived)"
                                  }])

    print("Clean slate setup complete.")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Navigate to Settings/Users or main dashboard
ensure_firefox "http://localhost:8069/web#action=base.action_res_users"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="