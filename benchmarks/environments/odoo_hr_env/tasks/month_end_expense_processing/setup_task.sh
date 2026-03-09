#!/bin/bash
echo "=== Setting up month_end_expense_processing task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/expense_processing_result.json
rm -f /tmp/expense_processing_gt.json

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, time, datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
user = 'admin'
pwd = 'admin'

uid = None
for attempt in range(20):
    try:
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, user, pwd, {})
        if uid:
            break
    except Exception:
        pass
    time.sleep(5)

if not uid:
    print("ERROR: Could not authenticate to Odoo", file=sys.stderr)
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def exe(model, method, args, kwargs=None):
    return models.execute_kw(db, uid, pwd, model, method, args, kwargs or {})

def find_employee(name):
    ids = exe('hr.employee', 'search', [[['name', '=', name]]])
    return ids[0] if ids else None

# Target employees and their draft expenses
target_employees = [
    {
        'name': 'Anita Oliver',
        'expense_name': 'Client Entertainment - Q4',
        'total_amount': 120.00,
    },
    {
        'name': 'Sharlene Rhodes',
        'expense_name': 'Travel - Client Site Visit',
        'total_amount': 340.00,
    },
    {
        'name': 'Paul Williams',
        'expense_name': 'Training Materials and Certification',
        'total_amount': 85.00,
    },
]

# --- Get expense product (expense category) ---
# Try to find a standard "General Expenses" product
expense_products = exe('hr.expense', 'fields_get', [], {'attributes': ['string']})

# Get a suitable expense product
products = exe('product.product', 'search_read',
               [[['can_be_expensed', '=', True]]],
               {'fields': ['id', 'name'], 'limit': 5})
if not products:
    # Fallback: search product templates
    product_tmpls = exe('product.template', 'search_read',
                        [[['can_be_expensed', '=', True]]],
                        {'fields': ['id', 'name', 'product_variant_ids'], 'limit': 5})
    if product_tmpls:
        products = [{'id': t['product_variant_ids'][0], 'name': t['name']}
                    for t in product_tmpls if t.get('product_variant_ids')]

if not products:
    print("ERROR: No expense-eligible products found", file=sys.stderr)
    sys.exit(1)

expense_product_id = products[0]['id']
print(f"Using expense product: {products[0]['name']} (id={expense_product_id})")

# Get company currency
companies = exe('res.company', 'search_read', [[]], {'fields': ['id', 'currency_id'], 'limit': 1})
currency_id = companies[0]['currency_id'][0] if companies else None

target_emp_ids = []
created_expense_ids = {}

for emp_info in target_employees:
    name = emp_info['name']
    emp_id = find_employee(name)
    if not emp_id:
        print(f"WARNING: Employee '{name}' not found — skipping", file=sys.stderr)
        continue

    # --- Remove any existing draft expenses for this employee to get clean slate ---
    existing_expenses = exe('hr.expense', 'search',
                            [[['employee_id', '=', emp_id], ['sheet_id', '=', False]]])
    if existing_expenses:
        try:
            exe('hr.expense', 'unlink', [existing_expenses])
            print(f"Removed {len(existing_expenses)} existing draft expenses for '{name}'")
        except Exception as e:
            print(f"Warning: could not remove existing expenses for {name}: {e}", file=sys.stderr)

    # --- Remove existing expense sheets for this employee ---
    existing_sheets = exe('hr.expense.sheet', 'search',
                          [[['employee_id', '=', emp_id]]])
    if existing_sheets:
        for sheet_id in existing_sheets:
            sheet_data = exe('hr.expense.sheet', 'read', [[sheet_id]], {'fields': ['state']})
            if sheet_data:
                state = sheet_data[0].get('state', 'draft')
                if state in ['draft', 'submit']:
                    try:
                        if state == 'submit':
                            exe('hr.expense.sheet', 'action_reset_expense_sheets', [[sheet_id]])
                        exe('hr.expense.sheet', 'unlink', [[sheet_id]])
                    except Exception as e:
                        print(f"Warning: could not remove sheet {sheet_id}: {e}", file=sys.stderr)

    # --- Create a fresh draft expense ---
    try:
        expense_vals = {
            'name': emp_info['expense_name'],
            'employee_id': emp_id,
            'product_id': expense_product_id,
            'total_amount': emp_info['total_amount'],
            'date': str(datetime.date.today()),
        }
        if currency_id:
            expense_vals['currency_id'] = currency_id

        expense_id = exe('hr.expense', 'create', [expense_vals])
        print(f"Created draft expense for '{name}': '{emp_info['expense_name']}' "
              f"(id={expense_id}, total={emp_info['total_amount']})")
        created_expense_ids[name] = expense_id
        target_emp_ids.append(emp_id)
    except Exception as e:
        print(f"ERROR creating expense for '{name}': {e}", file=sys.stderr)

# Save ground truth
gt = {
    'target_employees': [
        {'name': emp_info['name'], 'expense_name': emp_info['expense_name'],
         'total_amount': emp_info['total_amount']}
        for emp_info in target_employees
    ],
    'target_employee_ids': target_emp_ids,
    'created_expense_ids': {k: v for k, v in created_expense_ids.items()},
    'paul_williams_id': find_employee('Paul Williams'),
    'anita_oliver_id': find_employee('Anita Oliver'),
    'sharlene_rhodes_id': find_employee('Sharlene Rhodes'),
}
with open('/tmp/expense_processing_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"\nSetup complete: Created draft expenses for {len(created_expense_ids)} employees.")
print("Agent must create expense reports, submit all 3, then approve Paul Williams's.")
PYTHON_EOF

date +%s > /tmp/task_start_timestamp
date +%s > /tmp/expense_processing_start_ts

# Baseline recording (Pattern 1): initial count of submitted expense sheets for 3 target employees (expect 0)
python3 -c "
import xmlrpc.client, json
url='http://localhost:8069'; db='odoo_hr'; pwd='admin'
common=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid=common.authenticate(db,'admin',pwd,{})
models=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
with open('/tmp/expense_processing_gt.json') as f: gt=json.load(f)
emp_ids=[v for k,v in gt.items() if k.endswith('_id') and k!='created_expense_ids' and v]
count=models.execute_kw(db,uid,pwd,'hr.expense.sheet','search_count',
  [[['employee_id','in',gt['target_employee_ids']],['state','not in',['draft']]]])
with open('/tmp/initial_submitted_sheets_count','w') as f: f.write(str(count))
print(f'Baseline: {count} submitted expense sheets (expect 0)')
" 2>/dev/null || echo "0" > /tmp/initial_submitted_sheets_count

ensure_firefox "http://localhost:8069/web#action=hr_expense.action_hr_expense_form"
sleep 3

take_screenshot /tmp/expense_processing_start.png

echo "Task start: Agent must process draft expenses for 3 employees."
echo "=== month_end_expense_processing setup complete ==="
