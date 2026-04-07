#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up approve_expense_report task ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Setup Data via XML-RPC
# This script ensures Eli Lambert exists, creates products if needed,
# creates the expense report, adds lines, and submits it.
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import datetime
import json

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("ERROR: Authentication failed", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Find Employee Eli Lambert
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Eli Lambert']]])
    if not emp_ids:
        print("ERROR: Employee Eli Lambert not found. Is demo data loaded?", file=sys.stderr)
        sys.exit(1)
    emp_id = emp_ids[0]

    # 2. Check if Report already exists (cleanup or reuse)
    # We remove it to ensure a clean state (submitted, not already approved)
    existing_ids = models.execute_kw(db, uid, password, 'hr.expense.sheet', 'search',
        [[['name', '=', 'Q4 Digital Marketing Conference'], ['employee_id', '=', emp_id]]])
    
    if existing_ids:
        # Try to reset to draft and delete to start fresh
        try:
            models.execute_kw(db, uid, password, 'hr.expense.sheet', 'action_reset_expense_sheets', [existing_ids])
            models.execute_kw(db, uid, password, 'hr.expense.sheet', 'unlink', [existing_ids])
            print("Removed existing expense report.")
        except Exception as e:
            print(f"Warning cleaning up: {e}", file=sys.stderr)

    # 3. Create/Find Expense Products
    def get_product_id(name, price):
        # Try to find existing
        ids = models.execute_kw(db, uid, password, 'product.product', 'search',
            [[['name', '=', name], ['can_be_expensed', '=', True]]])
        if ids:
            return ids[0]
        # Create
        return models.execute_kw(db, uid, password, 'product.product', 'create', [{
            'name': name,
            'list_price': price,
            'standard_price': price,
            'can_be_expensed': True,
            'type': 'service'
        }])

    p_conf = get_product_id("Conference Registration", 350.0)
    p_hotel = get_product_id("Hotel Accommodation", 480.0)
    p_meals = get_product_id("Meals", 95.0)

    # 4. Create Expense Lines first (Odoo flow often creates expenses then attaches to sheet)
    # Or create sheet and lines together. We'll create expenses then the sheet.
    expense_ids = []
    
    # Expense 1
    eid1 = models.execute_kw(db, uid, password, 'hr.expense', 'create', [{
        'name': 'Conference Registration - DigiMarket Summit',
        'product_id': p_conf,
        'total_amount_currency': 350.0,
        'employee_id': emp_id,
        'quantity': 1,
        'date': (datetime.date.today() - datetime.timedelta(days=5)).strftime('%Y-%m-%d')
    }])
    expense_ids.append(eid1)

    # Expense 2
    eid2 = models.execute_kw(db, uid, password, 'hr.expense', 'create', [{
        'name': 'Hotel Accommodation - 3 nights',
        'product_id': p_hotel,
        'total_amount_currency': 480.0,
        'employee_id': emp_id,
        'quantity': 1,
        'date': (datetime.date.today() - datetime.timedelta(days=4)).strftime('%Y-%m-%d')
    }])
    expense_ids.append(eid2)

    # Expense 3
    eid3 = models.execute_kw(db, uid, password, 'hr.expense', 'create', [{
        'name': 'Meals during conference',
        'product_id': p_meals,
        'total_amount_currency': 95.0,
        'employee_id': emp_id,
        'quantity': 1,
        'date': (datetime.date.today() - datetime.timedelta(days=3)).strftime('%Y-%m-%d')
    }])
    expense_ids.append(eid3)

    # 5. Create Expense Sheet (Report)
    sheet_id = models.execute_kw(db, uid, password, 'hr.expense.sheet', 'create', [{
        'name': 'Q4 Digital Marketing Conference',
        'employee_id': emp_id,
        'expense_line_ids': [[6, 0, expense_ids]]
    }])

    # 6. Submit the Sheet
    # Submitting puts it in 'submit' state (or 'reported' depending on version nuance)
    models.execute_kw(db, uid, password, 'hr.expense.sheet', 'action_submit_sheet', [[sheet_id]])

    # 7. Verify Initial State and Record
    sheet_data = models.execute_kw(db, uid, password, 'hr.expense.sheet', 'read',
        [[sheet_id]], {'fields': ['id', 'state', 'total_amount']})
    
    if sheet_data:
        data = sheet_data[0]
        initial_state = {
            'id': data['id'],
            'initial_state': data['state'],
            'initial_amount': data['total_amount']
        }
        with open('/tmp/initial_state.json', 'w') as f:
            json.dump(initial_state, f)
        print(f"Setup complete. Report ID: {data['id']}, State: {data['state']}")
    else:
        print("ERROR: Failed to read back created sheet", file=sys.stderr)
        sys.exit(1)

except Exception as e:
    print(f"CRITICAL SETUP ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# 3. Launch Firefox and navigate to Expenses
# We use the 'Reports to Approve' action ID if possible, or just the main app
ensure_firefox "http://localhost:8069/web#action=hr_expense.action_hr_expense_sheet_all_to_approve"
sleep 5

# 4. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="

<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
