#!/bin/bash
echo "=== Setting up create_expense_report task ==="

source /workspace/scripts/task_utils.sh

# Remove any existing "Client Meeting - Q4 Strategy" expenses for Ernest Reed
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    emp_ids = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                                [[['name', '=', 'Ernest Reed']]])
    if not emp_ids:
        print("ERROR: Employee 'Ernest Reed' not found (Odoo demo data missing?)", file=sys.stderr)
        sys.exit(1)
    emp_id = emp_ids[0]

    # Remove matching expenses
    existing = models.execute_kw(db, uid, 'admin', 'hr.expense', 'search',
                                 [[['employee_id', '=', emp_id],
                                   ['name', 'ilike', 'Client Meeting']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'hr.expense', 'unlink', [existing])
        print(f"Removed {len(existing)} existing 'Client Meeting' expense(s) for Ernest Reed")
    else:
        print("No existing target expenses for Ernest Reed — clean slate")
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Navigate to the New Expense form — this is where the agent starts creating the expense.
# Shows a blank expense form; agent must fill in description, amount, and set Employee to Ernest Reed.
# action=380 (My Expenses) with view_type=form opens a blank new expense form.
ensure_firefox "http://localhost:8069/web#action=380&view_type=form"
sleep 4

take_screenshot /tmp/task_start.png

echo "Task start state: New Expense form (blank). Agent must fill in description, total, set Employee to Ernest Reed, then create the report."
echo "=== create_expense_report task setup complete ==="
