#!/bin/bash
set -e
echo "=== Setting up adjust_approve_allocation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Use Python to set up the specific data scenario
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import time

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("Authentication failed", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Find Employee Randall Lewis
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search',
                                [[['name', '=', 'Randall Lewis']]])
    if not emp_ids:
        print("Employee Randall Lewis not found", file=sys.stderr)
        sys.exit(1)
    emp_id = emp_ids[0]

    # 2. Find or Create 'Compensatory Days' Leave Type
    # We look for a type that requires allocation='yes' (no limit) or similar
    # "Compensatory Days" is standard in demo data
    leave_type_ids = models.execute_kw(db, uid, password, 'hr.leave.type', 'search',
                                       [[['name', 'ilike', 'Compensatory']]])
    
    if leave_type_ids:
        leave_type_id = leave_type_ids[0]
    else:
        # Fallback: Find any type that allows allocation
        print("Compensatory Days type not found, searching fallback...", file=sys.stderr)
        leave_type_ids = models.execute_kw(db, uid, password, 'hr.leave.type', 'search',
                                           [[['requires_allocation', '=', 'yes']]], {'limit': 1})
        if not leave_type_ids:
            # Create if absolutely nothing exists (unlikely in this env)
            leave_type_id = models.execute_kw(db, uid, password, 'hr.leave.type', 'create', [{
                'name': 'Compensatory Days',
                'requires_allocation': 'yes',
                'request_unit': 'day'
            }])
        else:
            leave_type_id = leave_type_ids[0]

    # 3. Clean up existing allocations for this employee to ensure clean state
    # We remove anything in draft/confirm/validate to avoid confusion
    existing_allocs = models.execute_kw(db, uid, password, 'hr.leave.allocation', 'search',
                                        [[['employee_id', '=', emp_id]]])
    if existing_allocs:
        # Move to draft to allow deletion
        try:
            models.execute_kw(db, uid, password, 'hr.leave.allocation', 'action_draft', [existing_allocs])
        except Exception:
            pass
        models.execute_kw(db, uid, password, 'hr.leave.allocation', 'unlink', [existing_allocs])
        print(f"Cleaned up {len(existing_allocs)} existing allocations.")

    # 4. Create the Scenario: Pending Allocation for 5 Days
    allocation_id = models.execute_kw(db, uid, password, 'hr.leave.allocation', 'create', [{
        'name': 'Overtime Adjustment Request',
        'employee_id': emp_id,
        'holiday_status_id': leave_type_id,
        'number_of_days': 5.0,
        'allocation_type': 'regular',
        'state': 'confirm'  # 'confirm' = To Approve
    }])
    
    # Ensure it is in 'confirm' state (some configs auto-validate for admin)
    # If it auto-validated, reset to draft and confirm
    current_state = models.execute_kw(db, uid, password, 'hr.leave.allocation', 'read',
                                      [[allocation_id]], {'fields': ['state']})[0]['state']
    
    if current_state == 'validate':
        models.execute_kw(db, uid, password, 'hr.leave.allocation', 'action_draft', [[allocation_id]])
        models.execute_kw(db, uid, password, 'hr.leave.allocation', 'action_confirm', [[allocation_id]])

    print(f"Created pending allocation ID {allocation_id} for Randall Lewis (5.0 days)")
    
    # Save ID for verification
    with open('/tmp/target_allocation_id.txt', 'w') as f:
        f.write(str(allocation_id))

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox directly to the Allocations to Approve page to save navigation time
# Action ID for "Allocations" under Approvals often varies, so we use the generic menu action if specific not found
# Trying standard External ID for "Allocations" menu
echo "Launching Firefox..."
ensure_firefox "http://localhost:8069/web#action=hr_holidays.hr_leave_allocation_action_approve_department"
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="