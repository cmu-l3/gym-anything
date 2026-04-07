#!/bin/bash
set -e
echo "=== Setting up schedule_employee_activity task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Record initial activity state for Marc Demo
# We need to know how many activities exist to detect if a new one is added
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoo_hr"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # Find Marc Demo
    emp_ids = models.execute_kw(db, uid, password, "hr.employee", "search",
                                [[["name", "=", "Marc Demo"]]])
    if not emp_ids:
        print("ERROR: Employee 'Marc Demo' not found", file=sys.stderr)
        sys.exit(1)
    
    emp_id = emp_ids[0]
    
    # Count existing activities
    # res_model='hr.employee' AND res_id=emp_id
    count = models.execute_kw(db, uid, password, "mail.activity", "search_count",
                              [[["res_model", "=", "hr.employee"],
                                ["res_id", "=", emp_id]]])
    
    with open("/tmp/initial_activity_count.txt", "w") as f:
        f.write(str(count))
        
    print(f"Marc Demo (id={emp_id}) has {count} existing activities.")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is running and navigated to the Employees app (List View)
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my&view_type=list"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="