#!/bin/bash
# Setup script for employee_expense_report task
# Creates an employee "Sarah Chen", necessary expense products, and the claim text file.

echo "=== Setting up employee_expense_report ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    if curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null; then
        echo "Odoo XML-RPC ready."
        break
    fi
    sleep 3
done
sleep 2

# Create Text File with Claim Details
cat > /home/ga/Desktop/expense_claim_sarah_chen.txt << 'EOF'
═══════════════════════════════════════════════════
        EXPENSE REIMBURSEMENT CLAIM FORM
═══════════════════════════════════════════════════

Employee Name:    Sarah Chen
Department:       Sales
Event:            Pacific Northwest Supply Chain Expo 2024
Travel Dates:     November 11–13, 2024

───────────────────────────────────────────────────
ITEMIZED EXPENSES
───────────────────────────────────────────────────

1. Hotel Accommodation (3 nights)
   Vendor:   Pacific Crest Hotel
   Amount:   $487.50
   Date:     2024-11-11

2. Conference Registration Fee
   Vendor:   PN Supply Chain Expo
   Amount:   $375.00
   Date:     2024-11-11

3. Airfare – Round Trip (Portland, OR)
   Vendor:   United Airlines
   Amount:   $312.00
   Date:     2024-11-11

4. Meals & Entertainment
   Amount:   $156.75
   Date:     2024-11-13

5. Ground Transportation (Taxi/Rideshare)
   Amount:   $89.40
   Date:     2024-11-13

───────────────────────────────────────────────────
TOTAL CLAIMED:    $1,420.65
───────────────────────────────────────────────────

Approved by: Mitchell Admin
EOF

chmod 666 /home/ga/Desktop/expense_claim_sarah_chen.txt

# Use Python to set up Odoo data
python3 << 'PYEOF'
import xmlrpc.client
import sys

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

# 1. Install hr_expense module if not installed (usually installed in demo, but safe to check)
# In standard Odoo demo, it might be 'hr_expense'.
# We assume the environment has it, or we try to install it.
# (Skipping module installation in script to avoid long timeouts, assuming env has it or user installs it)

# 2. Create Employee "Sarah Chen"
existing_emp = execute('hr.employee', 'search_read', [[['name', '=', 'Sarah Chen']]], {'fields': ['id']})
if existing_emp:
    emp_id = existing_emp[0]['id']
    print(f"Using existing employee: Sarah Chen (id={emp_id})")
else:
    # Get a department id (Sales)
    depts = execute('hr.department', 'search_read', [[['name', 'ilike', 'Sales']]], {'fields': ['id'], 'limit': 1})
    dept_id = depts[0]['id'] if depts else False
    
    emp_id = execute('hr.employee', 'create', [{
        'name': 'Sarah Chen',
        'department_id': dept_id,
        'work_email': 'sarah.chen@example.com',
        'work_phone': '+1-555-0199'
    }])
    print(f"Created employee: Sarah Chen (id={emp_id})")

# 3. Create Expense Products
products_to_create = [
    {'name': 'Hotel Accommodation', 'default_code': 'EXP_HOTEL', 'standard_price': 0.0},
    {'name': 'Conference Registration', 'default_code': 'EXP_CONF', 'standard_price': 0.0},
    {'name': 'Airfare', 'default_code': 'EXP_AIR', 'standard_price': 0.0},
    {'name': 'Meals', 'default_code': 'EXP_MEAL', 'standard_price': 0.0},
    {'name': 'Ground Transportation', 'default_code': 'EXP_TAXI', 'standard_price': 0.0}
]

for p in products_to_create:
    # Check if exists
    existing = execute('product.product', 'search_read', [[['name', '=', p['name']], ['can_be_expensed', '=', True]]], {'fields': ['id']})
    if not existing:
        execute('product.product', 'create', [{
            'name': p['name'],
            'default_code': p['default_code'],
            'can_be_expensed': True,
            'type': 'service',
            'standard_price': p['standard_price'],
            'purchase_ok': False,
            'sale_ok': False,
        }])
        print(f"Created expense product: {p['name']}")
    else:
        print(f"Expense product exists: {p['name']}")

print("Setup complete.")
PYEOF

# Ensure Firefox is open to Odoo
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
fi

# Capture initial state screenshot
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup script finished ==="