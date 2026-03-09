#!/bin/bash
# Setup script for employee_expense_approval task
# Creates employee "Sarah Mitchell" with a submitted expense report.
# Report: "Q1 Client Visit - Chicago" with 3 expense items, total ~$847.50

echo "=== Setting up employee_expense_approval ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
}

echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Check if hr_expense module is installed
echo "Checking if Expenses module is installed..."
EXPENSE_CHECK=$(python3 -c "
import xmlrpc.client
common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
uid = common.authenticate('odoo_demo', 'admin@example.com', 'admin', {})
models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')
try:
    result = models.execute_kw('odoo_demo', uid, 'admin', 'ir.module.module', 'search_read',
        [[['name', '=', 'hr_expense'], ['state', '=', 'installed']]],
        {'fields': ['name', 'state'], 'limit': 1})
    print('installed' if result else 'not_installed')
except:
    print('error')
" 2>/dev/null)

echo "Expenses module status: $EXPENSE_CHECK"

if [ "$EXPENSE_CHECK" != "installed" ]; then
    echo "WARNING: hr_expense module not installed. Attempting to install..."
    python3 -c "
import xmlrpc.client
common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
uid = common.authenticate('odoo_demo', 'admin@example.com', 'admin', {})
models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')
modules = models.execute_kw('odoo_demo', uid, 'admin', 'ir.module.module', 'search_read',
    [[['name', '=', 'hr_expense']]],
    {'fields': ['id', 'name', 'state'], 'limit': 1})
if modules:
    if modules[0]['state'] != 'installed':
        models.execute_kw('odoo_demo', uid, 'admin', 'ir.module.module', 'button_immediate_install',
            [[modules[0]['id']]])
        print('Install initiated')
    else:
        print('Already installed')
else:
    print('Module not found in registry')
" 2>/dev/null
    sleep 15  # Wait for installation
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
from datetime import date, timedelta

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    if not uid:
        print("ERROR: Authentication failed!", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"ERROR: Cannot connect to Odoo: {e}", file=sys.stderr)
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# ─── Check if expense models are available ───────────────────────────────────
try:
    test = execute('hr.expense', 'search_read', [[]], {'fields': ['id'], 'limit': 1})
    print("hr.expense model available ✓")
except Exception as e:
    print(f"ERROR: hr.expense model not available: {e}", file=sys.stderr)
    print("The Expenses module (hr_expense) may not be installed in this Odoo instance.")
    # Create fallback setup data
    setup_data = {
        'error': 'hr_expense_not_installed',
        'employee_name': 'Sarah Mitchell',
        'expense_report_name': 'Q1 Client Visit - Chicago',
    }
    with open('/tmp/expense_approval_setup.json', 'w') as f:
        json.dump(setup_data, f, indent=2)
    sys.exit(0)

EMPLOYEE_NAME = 'Sarah Mitchell'
REPORT_NAME = 'Q1 Client Visit - Chicago'

# ─── Create or find the employee ─────────────────────────────────────────────
existing_emp = execute('hr.employee', 'search_read',
    [[['name', '=', EMPLOYEE_NAME], ['active', '=', True]]],
    {'fields': ['id', 'name', 'address_home_id'], 'limit': 1})

if existing_emp:
    employee_id = existing_emp[0]['id']
    print(f"Using existing employee: {EMPLOYEE_NAME} (id={employee_id})")
else:
    # Create the employee's home address (res.partner)
    home_addr_id = execute('res.partner', 'create', [{
        'name': EMPLOYEE_NAME,
        'is_company': False,
        'email': 'sarah.mitchell@company.example.com',
        'type': 'private',
    }])

    employee_id = execute('hr.employee', 'create', [{
        'name': EMPLOYEE_NAME,
        'work_email': 'sarah.mitchell@company.example.com',
        'job_title': 'Regional Sales Representative',
        'address_home_id': home_addr_id,
    }])
    print(f"Created employee: {EMPLOYEE_NAME} (id={employee_id})")

# ─── Find expense product category (for expense line items) ──────────────────
# In Odoo, expenses reference products that are set up as expense categories
# Look for expense product(s) from demo data, or create them
expense_products = execute('product.product', 'search_read',
    [[['can_be_expensed', '=', True], ['active', '=', True]]],
    {'fields': ['id', 'name', 'standard_price', 'uom_id'], 'limit': 10})

if not expense_products:
    # Create expense products
    tmpl_hotel = execute('product.template', 'create', [{
        'name': 'Hotel & Accommodation',
        'type': 'service',
        'can_be_expensed': True,
        'standard_price': 1.0,
        'sale_ok': False,
        'purchase_ok': False,
    }])
    hotel_product = execute('product.product', 'search_read',
        [[['product_tmpl_id', '=', tmpl_hotel]]],
        {'fields': ['id', 'name'], 'limit': 1})[0]
    expense_products = [hotel_product]

expense_product_id = expense_products[0]['id']

# Look for more expense product types
def find_or_use_default_expense_product(preferred_name_keyword):
    for p in expense_products:
        if preferred_name_keyword.lower() in p.get('name', '').lower():
            return p['id']
    return expense_products[0]['id']  # fallback to first

# ─── Clean up any pre-existing expense report for this employee ───────────────
existing_sheets = execute('hr.expense.sheet', 'search_read',
    [[['employee_id', '=', employee_id], ['name', '=', REPORT_NAME]]],
    {'fields': ['id', 'name', 'state']})
if existing_sheets:
    for sheet in existing_sheets:
        if sheet.get('state') in ['draft', 'submit']:
            try:
                execute('hr.expense.sheet', 'write', [[sheet['id']], {'state': 'cancel'}])
                execute('hr.expense.sheet', 'unlink', [[sheet['id']]])
            except Exception:
                pass

# ─── Define the 3 expense items ──────────────────────────────────────────────
yesterday = (date.today() - timedelta(days=1)).strftime('%Y-%m-%d')
two_days_ago = (date.today() - timedelta(days=2)).strftime('%Y-%m-%d')
three_days_ago = (date.today() - timedelta(days=3)).strftime('%Y-%m-%d')

EXPENSE_ITEMS = [
    {
        'name': 'Hotel - Chicago Marriott Magnificent Mile (2 nights)',
        'unit_amount': 285.00,
        'quantity': 2.0,
        'date': two_days_ago,
        'product_id': expense_product_id,
    },
    {
        'name': 'Business Meals - Client Dinner',
        'unit_amount': 127.50,
        'quantity': 1.0,
        'date': two_days_ago,
        'product_id': find_or_use_default_expense_product('meal') if len(expense_products) > 1 else expense_product_id,
    },
    {
        'name': 'Flight - PDX to ORD Round Trip',
        'unit_amount': 420.00,
        'quantity': 1.0,
        'date': three_days_ago,
        'product_id': find_or_use_default_expense_product('travel') if len(expense_products) > 1 else expense_product_id,
    },
]

total_amount = sum(e['unit_amount'] * e['quantity'] for e in EXPENSE_ITEMS)

# ─── Create the expense items ─────────────────────────────────────────────────
expense_ids = []
for item in EXPENSE_ITEMS:
    exp_id = execute('hr.expense', 'create', [{
        'name': item['name'],
        'employee_id': employee_id,
        'product_id': item['product_id'],
        'unit_amount': item['unit_amount'],
        'quantity': item['quantity'],
        'date': item['date'],
        'description': f'Business expense for {REPORT_NAME}',
    }])
    expense_ids.append(exp_id)
    print(f"Created expense: {item['name']} - ${item['unit_amount'] * item['quantity']:.2f}")

# ─── Create the expense sheet (report) ────────────────────────────────────────
sheet_id = execute('hr.expense.sheet', 'create', [{
    'name': REPORT_NAME,
    'employee_id': employee_id,
    'expense_line_ids': [(4, eid) for eid in expense_ids],
}])
print(f"Created expense report: {REPORT_NAME} (id={sheet_id})")

# ─── Submit the expense report ────────────────────────────────────────────────
try:
    execute('hr.expense.sheet', 'action_submit_sheet', [[sheet_id]])
    print("Expense report submitted (state: submit) ✓")
except Exception as e:
    print(f"Warning: Could not submit via action_submit_sheet: {e}")
    # Try alternative method
    try:
        execute('hr.expense.sheet', 'write', [[sheet_id], {'state': 'submit'}])
        print("Set state to 'submit' directly")
    except Exception as e2:
        print(f"Warning: Could not set state: {e2}")

# ─── Verify the final state ────────────────────────────────────────────────────
sheet_data = execute('hr.expense.sheet', 'read', [[sheet_id]],
    {'fields': ['name', 'state', 'total_amount', 'employee_id']})[0]
print(f"Expense report state: {sheet_data['state']}")
print(f"Total amount: ${sheet_data['total_amount']:.2f}")

# ─── Save setup data ──────────────────────────────────────────────────────────
setup_data = {
    'employee_id': employee_id,
    'employee_name': EMPLOYEE_NAME,
    'expense_sheet_id': sheet_id,
    'expense_sheet_name': REPORT_NAME,
    'expense_ids': expense_ids,
    'total_amount': total_amount,
    'initial_state': sheet_data['state'],
}
with open('/tmp/expense_approval_setup.json', 'w') as f:
    json.dump(setup_data, f, indent=2)

print(f"\n=== Setup Summary ===")
print(f"Employee:       {EMPLOYEE_NAME}")
print(f"Report:         {REPORT_NAME}")
print(f"Expenses:       {len(expense_ids)} items, total ${total_amount:.2f}")
for item in EXPENSE_ITEMS:
    print(f"  - {item['name']}: ${item['unit_amount'] * item['quantity']:.2f}")
print(f"Current state:  {sheet_data['state']}")
print(f"Agent task:     approve → post journal → register payment")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Python setup script failed!"
    exit 1
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is open at Odoo Expenses
FIREFOX_PID=$(pgrep -f firefox 2>/dev/null | head -1)
if [ -z "$FIREFOX_PID" ]; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/odoo/expenses' &" 2>/dev/null
    sleep 5
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Setup data: /tmp/expense_approval_setup.json"
