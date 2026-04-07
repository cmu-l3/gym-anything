#!/bin/bash
set -e
echo "=== Setting up Purge Stale Leave Requests task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the specific data scenario using Python/XML-RPC
python3 << 'PYTHON_EOF'
import xmlrpc.client
import datetime
import json
import sys
import random

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Find suitable employees (Demo data)
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[]])
    if not emp_ids:
        print("Error: No employees found", file=sys.stderr)
        sys.exit(1)

    # 2. Find a suitable leave type (Paid Time Off or generic)
    # Try to find one that doesn't strictly require allocation to simplify setup, 
    # or ensure we use one where admin has allocation. 
    # "Sick Time Off" usually doesn't require allocation in demo data.
    leave_types = models.execute_kw(db, uid, password, 'hr.leave.type', 'search_read', 
                                    [[['requires_allocation', '=', 'no']]], 
                                    {'fields': ['id', 'name'], 'limit': 1})
    
    if not leave_types:
        # Fallback to any type
        leave_types = models.execute_kw(db, uid, password, 'hr.leave.type', 'search_read', 
                                        [[]], {'fields': ['id', 'name'], 'limit': 1})
    
    leave_type_id = leave_types[0]['id']
    print(f"Using Leave Type: {leave_types[0]['name']}")

    today = datetime.date.today()
    
    # Helper to create leave
    def create_leave(emp_id, date_offset_days, status='draft', desc="Task Setup"):
        start = today + datetime.timedelta(days=date_offset_days)
        # 1 day duration
        end = start 
        
        vals = {
            'holiday_status_id': leave_type_id,
            'employee_id': emp_id,
            'date_from': f'{start} 09:00:00',
            'date_to': f'{end} 17:00:00',
            'name': desc,
            'request_date_from': str(start),
            'request_date_to': str(end),
        }
        
        leave_id = models.execute_kw(db, uid, password, 'hr.leave', 'create', [vals])
        
        # Adjust status
        if status != 'draft':
            # Confirm (To Approve)
            models.execute_kw(db, uid, password, 'hr.leave', 'action_confirm', [[leave_id]])
            
            if status == 'validate':
                # Approve
                models.execute_kw(db, uid, password, 'hr.leave', 'action_validate', [[leave_id]])
        
        # For 'draft', Odoo created it as draft/confirm depending on user context. 
        # Since we are admin, it might auto-confirm or stay draft. 
        # We enforce draft by resetting if needed, though 'create' usually makes confirm for admin.
        # Actually, for standard users it is draft (to submit). For admin, it might jump.
        # Let's check state.
        state = models.execute_kw(db, uid, password, 'hr.leave', 'read', [[leave_id]], {'fields': ['state']})[0]['state']
        
        if status == 'draft' and state != 'draft':
            # Try to reset to draft (refuse then reset? or just draft button?)
            # 'action_draft' is the method usually.
            try:
                models.execute_kw(db, uid, password, 'hr.leave', 'action_draft', [[leave_id]])
            except:
                pass
                
        return leave_id

    # --- SCENARIO CREATION ---
    
    scenario_data = {
        "stale_draft_ids": [],
        "future_draft_ids": [],
        "past_confirmed_ids": [],
        "future_confirmed_ids": []
    }

    # Use 'Mitchell Admin' (uid 1 is usually linked to emp id 1) or first available
    target_emp = emp_ids[0]

    print("Creating Stale Drafts (Target)...")
    # 3 Stale Drafts (Past)
    scenario_data["stale_draft_ids"].append(create_leave(target_emp, -30, 'draft', "Stale Draft 1"))
    scenario_data["stale_draft_ids"].append(create_leave(target_emp, -15, 'draft', "Stale Draft 2"))
    scenario_data["stale_draft_ids"].append(create_leave(target_emp, -5, 'draft', "Stale Draft 3"))

    print("Creating Future Drafts (Safety)...")
    # 2 Future Drafts
    scenario_data["future_draft_ids"].append(create_leave(target_emp, 10, 'draft', "Future Draft 1"))
    scenario_data["future_draft_ids"].append(create_leave(target_emp, 20, 'draft', "Future Draft 2"))

    print("Creating History/Active (Safety)...")
    # 2 Past Confirmed/Approved
    scenario_data["past_confirmed_ids"].append(create_leave(target_emp, -40, 'validate', "Past Approved"))
    scenario_data["past_confirmed_ids"].append(create_leave(target_emp, -10, 'confirm', "Past Pending")) # 'confirm' is 'To Approve'

    # 1 Future Confirmed/Approved
    scenario_data["future_confirmed_ids"].append(create_leave(target_emp, 5, 'confirm', "Future Pending"))

    # Save IDs to file for verification
    with open('/tmp/scenario_data.json', 'w') as f:
        json.dump(scenario_data, f)
        
    print("Scenario created successfully.")
    print(json.dumps(scenario_data, indent=2))

except Exception as e:
    print(f"Error creating data: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is open and logged in, navigated to Time Off
# We navigate to the list view of requests
ensure_firefox "http://localhost:8069/web#action=hr_holidays.hr_leave_action_my"

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="