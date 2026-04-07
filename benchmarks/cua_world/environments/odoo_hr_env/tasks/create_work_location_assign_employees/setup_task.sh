#!/bin/bash
set -e
echo "=== Setting up task: create_work_location_assign_employees ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Record initial state and ensure clean starting point
# We use Python/XML-RPC to interact with Odoo directly
python3 << 'PYEOF'
import xmlrpc.client, json, sys

url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    if not uid:
        print("ERROR: Authentication failed", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # --- Clean up any pre-existing target work location from a previous run ---
    target_name = "East Side Satellite Office"
    target_ids = models.execute_kw(db, uid, 'admin', 'hr.work.location', 'search',
                                    [[['name', '=', target_name]]])
    
    if target_ids:
        # Unlink employees from this WL first to avoid constraint errors
        emps_with_wl = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                                          [[['work_location_id', 'in', target_ids]]])
        if emps_with_wl:
            models.execute_kw(db, uid, 'admin', 'hr.employee', 'write',
                              [emps_with_wl, {'work_location_id': False}])
            print(f"Unlinked {len(emps_with_wl)} employees from existing target location.")
            
        models.execute_kw(db, uid, 'admin', 'hr.work.location', 'unlink', [target_ids])
        print(f"Cleaned up pre-existing work location(s): {target_ids}")

    # --- Clear work_location_id for the three target employees ---
    # This ensures the agent must actually perform the assignment
    emp_names = ['Marc Demo', 'Audrey Peterson', 'Randall Lewis']
    initial_state = {'employees': {}}
    
    for name in emp_names:
        emp_ids = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                                    [[['name', '=', name]]])
        if emp_ids:
            # Set work location to False (None)
            models.execute_kw(db, uid, 'admin', 'hr.employee', 'write',
                              [emp_ids, {'work_location_id': False}])
            initial_state['employees'][name] = {'id': emp_ids[0], 'work_location_id': None}
            print(f"Cleared work location for {name} (id={emp_ids[0]})")
        else:
            print(f"WARNING: Employee '{name}' not found!", file=sys.stderr)

    # Record initial work location count
    wl_count = models.execute_kw(db, uid, 'admin', 'hr.work.location', 'search_count', [[]])
    initial_state['work_location_count'] = wl_count
    print(f"Initial work location count: {wl_count}")

    with open('/tmp/initial_state.json', 'w') as f:
        json.dump(initial_state, f)

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Launch Firefox and navigate to Odoo Employees app
# This helps the agent start in the right context
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="