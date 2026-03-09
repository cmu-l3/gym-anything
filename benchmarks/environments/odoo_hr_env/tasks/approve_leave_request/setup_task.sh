#!/bin/bash
echo "=== Setting up approve_leave_request task ==="

source /workspace/scripts/task_utils.sh

# Ensure Rachel Perry has exactly one pending (confirm) leave request
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys, datetime
url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    emp_ids = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                                [[['name', '=', 'Rachel Perry']]])
    if not emp_ids:
        print("ERROR: Employee 'Rachel Perry' not found (Odoo demo data missing?)", file=sys.stderr)
        sys.exit(1)
    emp_id = emp_ids[0]

    # Check for existing confirmed leave request
    leave_ids = models.execute_kw(db, uid, 'admin', 'hr.leave', 'search',
                                  [[['employee_id', '=', emp_id],
                                    ['state', 'in', ['confirm', 'validate1']]]])

    if leave_ids:
        print(f"Rachel Perry already has pending leave request(s): {leave_ids}")
    else:
        # Find a leave type that doesn't require allocation
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
        future_start = today + datetime.timedelta(days=14)
        future_end = future_start + datetime.timedelta(days=4)

        leave_id = models.execute_kw(db, uid, 'admin', 'hr.leave', 'create', [{
            'holiday_status_id': leave_type_id,
            'employee_id': emp_id,
            'date_from': f'{future_start} 08:00:00',
            'date_to': f'{future_end} 17:00:00',
            'name': 'Annual vacation',
        }])
        models.execute_kw(db, uid, 'admin', 'hr.leave', 'action_confirm', [[leave_id]])
        print(f"Created pending leave for Rachel Perry (id={leave_id})")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Navigate to Time Off manager view
ensure_firefox "http://localhost:8069/web#action=hr_holidays.hr_leave_action_action_approve_department"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Time Off app. Rachel Perry has a pending leave request."
echo "Agent should find and approve Rachel Perry's leave request."
echo "=== approve_leave_request task setup complete ==="
