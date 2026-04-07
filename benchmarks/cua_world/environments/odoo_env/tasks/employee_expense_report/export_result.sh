#!/bin/bash
# Export script for employee_expense_report task
# Queries Odoo to find expense sheets and lines for Sarah Chen.

echo "=== Exporting employee_expense_report Result ==="

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Find Employee Sarah Chen
emps = execute('hr.employee', 'search_read', [[['name', '=', 'Sarah Chen']]], {'fields': ['id', 'name']})
if not emps:
    result = {'error': 'Employee Sarah Chen not found', 'passed': False}
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

emp_id = emps[0]['id']

# Find Expense Sheets (Reports) for this employee
# We look for sheets created recently (though Odoo doesn't easily expose create_date via search_read without extra config, we can assume ID order)
sheets = execute('hr.expense.sheet', 'search_read', 
    [[['employee_id', '=', emp_id]]], 
    {'fields': ['id', 'name', 'state', 'total_amount', 'expense_line_ids', 'accounting_date', 'create_date'], 'order': 'id desc', 'limit': 1})

report_found = False
report_data = {}
expenses_data = []

if sheets:
    sheet = sheets[0]
    report_found = True
    
    # Check for journal entry (account.move) linked to this sheet
    # Usually the sheet has an 'account_move_id' field if posted, or we search account.move for the ref
    # Let's try to fetch account_move_id field if it exists
    sheet_details = execute('hr.expense.sheet', 'read', [[sheet['id']]], {'fields': ['account_move_id']})
    move_id = sheet_details[0].get('account_move_id')
    
    move_state = 'unknown'
    if move_id:
        move_id_val = move_id[0] if isinstance(move_id, list) else move_id
        if move_id_val:
            moves = execute('account.move', 'read', [[move_id_val]], {'fields': ['state']})
            if moves:
                move_state = moves[0]['state']

    report_data = {
        'id': sheet['id'],
        'state': sheet['state'], # draft, submit, approve, post, done
        'total_amount': sheet['total_amount'],
        'move_state': move_state,
        'create_date': sheet.get('create_date', '')
    }

    # Fetch individual expenses in this sheet
    expense_ids = sheet['expense_line_ids']
    if expense_ids:
        expenses = execute('hr.expense', 'read', [expense_ids], 
            {'fields': ['name', 'total_amount', 'date', 'product_id', 'state']})
        for exp in expenses:
            expenses_data.append({
                'name': exp['name'],
                'amount': exp['total_amount'],
                'date': exp['date'],
                'state': exp['state'],
                'product': exp.get('product_id', [0, 'Unknown'])[1]
            })

result = {
    'report_found': report_found,
    'report': report_data,
    'expenses': expenses_data,
    'employee_id': emp_id,
    'task_start': int(sys.argv[1]) if len(sys.argv) > 1 else 0
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF $TASK_START

# Ensure permissions
chmod 666 /tmp/task_result.json