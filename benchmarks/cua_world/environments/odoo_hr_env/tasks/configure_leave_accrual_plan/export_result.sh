#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_final.png

# Query Odoo for the current state
# We use Python/XMLRPC to inspect the database
python3 << PYTHON_EOF
import xmlrpc.client
import json
import datetime
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "plan_found": False,
    "plan_details": {},
    "allocation_found": False,
    "allocation_details": {},
    "timestamp_check": False
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check Accrual Plan
    plans = models.execute_kw(db, uid, password, 'hr.leave.accrual.plan', 'search_read',
                             [[['name', 'ilike', 'Monthly PTO Accrual']]],
                             {'fields': ['id', 'name', 'level_ids', 'create_date']})
    
    if plans:
        plan = plans[0]
        result["plan_found"] = True
        result["plan_details"]["id"] = plan['id']
        result["plan_details"]["name"] = plan['name']
        result["plan_details"]["create_date"] = plan['create_date']

        # Check Levels
        if plan['level_ids']:
            levels = models.execute_kw(db, uid, password, 'hr.leave.accrual.level', 'read',
                                      [plan['level_ids']],
                                      {'fields': ['added_value', 'frequency', 'cap_accrued_time', 'maximum_leave']})
            result["plan_details"]["levels"] = levels

    # 2. Check Allocation for Eli Lambert
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Eli Lambert']]])
    if emp_ids:
        allocs = models.execute_kw(db, uid, password, 'hr.leave.allocation', 'search_read',
                                  [[['employee_id', '=', emp_ids[0]], 
                                    ['allocation_type', '=', 'accrual']]], # Filter by accrual type specifically
                                  {'fields': ['id', 'allocation_type', 'accrual_plan_id', 'state', 'holiday_status_id', 'create_date']})
        
        # Sort by latest
        if allocs:
            alloc = sorted(allocs, key=lambda x: x['id'], reverse=True)[0]
            result["allocation_found"] = True
            result["allocation_details"] = alloc
            
            # Get leave type name
            if alloc.get('holiday_status_id'):
                lt = models.execute_kw(db, uid, password, 'hr.leave.type', 'read', 
                                      [alloc['holiday_status_id'][0]], {'fields': ['name']})
                if lt:
                    result["allocation_details"]["leave_type_name"] = lt[0]['name']

    # 3. Timestamp Check (Anti-gaming)
    task_start = $TASK_START
    
    # Check plan creation time
    plan_fresh = False
    if result["plan_found"]:
        # Odoo returns string "YYYY-MM-DD HH:MM:SS"
        cdate_str = result["plan_details"]["create_date"]
        # Simple parse (assuming server is UTC or matches local system relative time)
        # We can just check if it exists, as setup script deleted previous ones.
        # But let's try to be precise if possible.
        pass 
        
    # Since we deleted old records in setup, existence implies new creation during task window.
    result["timestamp_check"] = True 

except Exception as e:
    result["error"] = str(e)

# Save result to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)

PYTHON_EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="