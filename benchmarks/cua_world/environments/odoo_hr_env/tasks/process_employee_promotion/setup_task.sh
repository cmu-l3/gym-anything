#!/bin/bash
set -e
echo "=== Setting up process_employee_promotion task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (timestamp check)
date +%s > /tmp/task_start_time.txt

# Capture Ernest Reed's initial field values (for anti-gaming comparison)
# We use Odoo's XML-RPC to get the clean database state
python3 << 'PYEOF'
import xmlrpc.client, json, sys, os

url = "http://localhost:8069"
db = "odoo_hr"
try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, "admin", "admin", {})
    if not uid:
        print("Authentication failed during setup", file=sys.stderr)
        sys.exit(1)
        
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # Find Ernest Reed
    emp_ids = models.execute_kw(db, uid, "admin", "hr.employee", "search",
                            [[["name", "=", "Ernest Reed"]]])
    if not emp_ids:
        print("ERROR: Ernest Reed not found in demo data", file=sys.stderr)
        sys.exit(1)

    # Read initial fields
    fields = ["job_title", "department_id", "job_id", "parent_id", "coach_id", 
              "work_phone", "work_email", "write_date"]
    data = models.execute_kw(db, uid, "admin", "hr.employee", "read",
                         [emp_ids[:1]], {"fields": fields})
                         
    with open("/tmp/ernest_reed_initial.json", "w") as f:
        json.dump(data[0], f)
        
    print(f"Captured initial state for Ernest Reed (id={emp_ids[0]})")
    
except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure Firefox is open and navigated to the Employees list view
# This puts the agent in the correct starting context
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"
sleep 5

# Maximize Firefox ensures all fields are visible without awkward scrolling
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for verification evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="