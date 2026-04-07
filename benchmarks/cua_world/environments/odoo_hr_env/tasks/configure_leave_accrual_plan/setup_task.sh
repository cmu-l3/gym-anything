#!/bin/bash
set -e
echo "=== Setting up configure_leave_accrual_plan task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# -------------------------------------------------------
# Clean State: Remove existing plan or allocations if they exist
# -------------------------------------------------------
echo "Ensuring clean state..."
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
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check for/remove existing "Monthly PTO Accrual" plan
    plans = models.execute_kw(db, uid, password, 'hr.leave.accrual.plan', 'search', 
                             [[['name', 'ilike', 'Monthly PTO Accrual']]])
    if plans:
        # Check if linked to allocations first
        allocs = models.execute_kw(db, uid, password, 'hr.leave.allocation', 'search',
                                  [[['accrual_plan_id', 'in', plans]]])
        if allocs:
             models.execute_kw(db, uid, password, 'hr.leave.allocation', 'unlink', [allocs])
             print(f"Removed {len(allocs)} linked allocations")
        
        models.execute_kw(db, uid, password, 'hr.leave.accrual.plan', 'unlink', [plans])
        print(f"Removed {len(plans)} existing accrual plans")

    # 2. Check for/remove existing "Paid Time Off" allocations for "Eli Lambert"
    # (To prevent confusion with pre-existing data)
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Eli Lambert']]])
    if emp_ids:
        emp_id = emp_ids[0]
        # Find 'Paid Time Off' type
        leave_types = models.execute_kw(db, uid, password, 'hr.leave.type', 'search', 
                                       [[['name', '=', 'Paid Time Off']]])
        if leave_types:
            allocs = models.execute_kw(db, uid, password, 'hr.leave.allocation', 'search',
                                      [[['employee_id', '=', emp_id], 
                                        ['holiday_status_id', 'in', leave_types]]])
            if allocs:
                # Must draft before delete usually, but unlink might work if admin
                try:
                    models.execute_kw(db, uid, password, 'hr.leave.allocation', 'action_refuse', [allocs])
                    models.execute_kw(db, uid, password, 'hr.leave.allocation', 'action_draft', [allocs])
                except:
                    pass
                models.execute_kw(db, uid, password, 'hr.leave.allocation', 'unlink', [allocs])
                print(f"Removed {len(allocs)} existing allocations for Eli Lambert")
except Exception as e:
    print(f"Setup warning: {e}")
PYTHON_EOF

# -------------------------------------------------------
# App Setup
# -------------------------------------------------------
# Launch Firefox and navigate to Time Off Dashboard
# The agent needs to navigate to Configuration from there
ensure_firefox "http://localhost:8069/web#action=hr_holidays.action_hr_holidays_dashboard"

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="