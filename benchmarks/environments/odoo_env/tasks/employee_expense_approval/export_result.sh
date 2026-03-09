#!/bin/bash
# Export script for employee_expense_approval task

echo "=== Exporting employee_expense_approval Result ==="

DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

if [ ! -f /tmp/expense_approval_setup.json ]; then
    echo '{"error": "setup_data_missing"}' > /tmp/employee_expense_approval_result.json
    exit 0
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
from datetime import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

with open('/tmp/expense_approval_setup.json') as f:
    setup = json.load(f)

if setup.get('error') == 'hr_expense_not_installed':
    result = {
        'error': 'hr_expense_not_installed',
        'task': 'employee_expense_approval',
        'employee_name': setup.get('employee_name'),
    }
    with open('/tmp/employee_expense_approval_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect: {e}'}
    with open('/tmp/employee_expense_approval_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

sheet_id = setup['expense_sheet_id']
employee_id = setup['employee_id']
expected_total = setup['total_amount']

task_start = 0
try:
    with open('/tmp/task_start_timestamp') as f:
        task_start = int(f.read().strip())
except Exception:
    pass

# ─── Query the expense sheet current state ────────────────────────────────────
try:
    sheets = execute('hr.expense.sheet', 'read', [[sheet_id]],
        {'fields': ['id', 'name', 'state', 'total_amount', 'employee_id',
                    'account_move_id', 'payment_state']})
    sheet = sheets[0] if sheets else {}
except Exception as e:
    sheet = {}
    print(f"Warning: Could not query expense sheet: {e}", file=sys.stderr)

sheet_state = sheet.get('state', 'unknown')
sheet_total = float(sheet.get('total_amount', 0))
account_move_id = sheet.get('account_move_id')
if isinstance(account_move_id, list):
    account_move_id = account_move_id[0]
payment_state = sheet.get('payment_state', 'not_paid')

# Odoo hr.expense.sheet states:
# draft -> submit (submitted) -> approve (approved/validated)
# -> post (accounting posted) -> done (paid)

is_approved = sheet_state in ['approve', 'post', 'done']
is_posted = sheet_state in ['post', 'done']
is_paid = sheet_state == 'done' or payment_state in ['paid', 'in_payment']

# Check if accounting entries were posted
journal_entries_posted = False
if account_move_id:
    try:
        moves = execute('account.move', 'read', [[account_move_id]],
            {'fields': ['state', 'amount_total']})
        if moves and moves[0].get('state') == 'posted':
            journal_entries_posted = True
    except Exception as e:
        print(f"Warning: Could not query journal entry: {e}")

# Also check via payment_state on the sheet
if payment_state in ['paid', 'in_payment']:
    is_paid = True

print(f"Expense sheet state: {sheet_state}")
print(f"  Approved: {is_approved}")
print(f"  Journal posted: {is_posted or journal_entries_posted}")
print(f"  Paid: {is_paid}")
print(f"  Total: ${sheet_total:.2f} (expected ${expected_total:.2f})")

result = {
    'task': 'employee_expense_approval',
    'employee_id': employee_id,
    'employee_name': setup['employee_name'],
    'sheet_id': sheet_id,
    'sheet_name': setup['expense_sheet_name'],
    'sheet_state': sheet_state,
    'sheet_total': sheet_total,
    'expected_total': expected_total,
    'is_approved': is_approved,
    'is_posted': is_posted or journal_entries_posted,
    'is_paid': is_paid,
    'payment_state': payment_state,
    'account_move_id': account_move_id,
    'task_start': task_start,
    'export_timestamp': datetime.now().isoformat(),
}

with open('/tmp/employee_expense_approval_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export Complete ==="
