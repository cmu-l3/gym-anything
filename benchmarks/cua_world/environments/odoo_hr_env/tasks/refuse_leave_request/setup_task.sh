#!/bin/bash
echo "=== Setting up refuse_leave_request task ==="

source /workspace/scripts/task_utils.sh

# Ensure Doris Cole has exactly one pending (confirm) leave request
# Outputs "LEAVE_ID=<id>" so the shell can read it for the navigation URL
LEAVE_ID=$(python3 << 'PYTHON_EOF'
import xmlrpc.client, sys, datetime
url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    emp_ids = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                                [[['name', '=', 'Doris Cole']]])
    if not emp_ids:
        print("ERROR: Employee 'Doris Cole' not found (Odoo demo data missing?)", file=sys.stderr)
        sys.exit(1)
    emp_id = emp_ids[0]

    # Check for existing leave requests
    leave_ids = models.execute_kw(db, uid, 'admin', 'hr.leave', 'search',
                                  [[['employee_id', '=', emp_id]]])

    confirmed_ids = []
    for lid in leave_ids:
        leave_data = models.execute_kw(db, uid, 'admin', 'hr.leave', 'read',
                                       [[lid]], {'fields': ['state']})
        if leave_data:
            state = leave_data[0]['state']
            if state == 'confirm':
                confirmed_ids.append(lid)
            elif state in ['validate', 'validate1']:
                try:
                    models.execute_kw(db, uid, 'admin', 'hr.leave', 'action_refuse', [[lid]])
                    models.execute_kw(db, uid, 'admin', 'hr.leave', 'action_draft', [[lid]])
                    models.execute_kw(db, uid, 'admin', 'hr.leave', 'action_confirm', [[lid]])
                    confirmed_ids.append(lid)
                    print(f"Reset leave {lid} to confirm state", file=sys.stderr)
                except Exception as e:
                    print(f"Warning: Could not reset leave {lid}: {e}", file=sys.stderr)
            elif state == 'refuse':
                try:
                    models.execute_kw(db, uid, 'admin', 'hr.leave', 'action_draft', [[lid]])
                    models.execute_kw(db, uid, 'admin', 'hr.leave', 'action_confirm', [[lid]])
                    confirmed_ids.append(lid)
                    print(f"Reset refused leave {lid} to confirm state", file=sys.stderr)
                except Exception as e:
                    print(f"Warning: Could not reset refused leave {lid}: {e}", file=sys.stderr)

    if confirmed_ids:
        print(f"Doris Cole has confirmed leave request(s): {confirmed_ids}", file=sys.stderr)
        # Print the first confirmed leave ID to stdout for the shell to capture
        print(confirmed_ids[0])
    else:
        # Create a new pending leave request
        leave_types = models.execute_kw(db, uid, 'admin', 'hr.leave.type', 'search_read',
                                        [[['requires_allocation', '=', 'no']]],
                                        {'fields': ['id', 'name'], 'limit': 5})
        if not leave_types:
            leave_types = models.execute_kw(db, uid, 'admin', 'hr.leave.type', 'search_read',
                                            [[]], {'fields': ['id', 'name'], 'limit': 1})
        if not leave_types:
            print("ERROR: No leave types found!", file=sys.stderr)
            sys.exit(1)
        leave_type_id = leave_types[0]['id']

        today = datetime.date.today()
        future_start = today + datetime.timedelta(days=21)
        future_end = future_start + datetime.timedelta(days=2)

        leave_id = models.execute_kw(db, uid, 'admin', 'hr.leave', 'create', [{
            'holiday_status_id': leave_type_id,
            'employee_id': emp_id,
            'date_from': f'{future_start} 08:00:00',
            'date_to': f'{future_end} 17:00:00',
            'name': 'Personal time off',
        }])
        models.execute_kw(db, uid, 'admin', 'hr.leave', 'action_confirm', [[leave_id]])
        print(f"Created pending leave for Doris Cole (id={leave_id})", file=sys.stderr)
        print(leave_id)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
)

echo "Doris Cole leave ID: $LEAVE_ID"

# Navigate directly to Doris Cole's specific leave request form.
# This gives a visually distinct start state from approve_leave_request (which shows the list view).
ensure_firefox "http://localhost:8069/web#action=hr_holidays.hr_leave_action_action_approve_department&id=${LEAVE_ID}&view_type=form"
sleep 4

take_screenshot /tmp/task_start.png

echo "Task start state: Doris Cole's 'Personal time off' leave request form (state=To Approve)."
echo "Agent should refuse this leave request."
echo "=== refuse_leave_request task setup complete ==="
