#!/bin/bash
set -e
echo "=== Setting up submit_expense_on_behalf task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the 'Meals' product exists and 'Marc Demo' is available
python3 -c "
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Ensure 'Meals' product exists
    meals_id = models.execute_kw(db, uid, password, 'product.product', 'search', [[['name', '=', 'Meals'], ['can_be_expensed', '=', True]]])
    if not meals_id:
        print('Creating Meals product...')
        models.execute_kw(db, uid, password, 'product.product', 'create', [{
            'name': 'Meals',
            'can_be_expensed': True,
            'standard_price': 10.0,
            'list_price': 10.0,
            'detailed_type': 'service'
        }])
    else:
        print('Meals product already exists.')

    # 2. Verify Marc Demo exists
    marc_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Marc Demo']]])
    if not marc_ids:
        print('Error: Marc Demo not found in database!')
        sys.exit(1)
        
    print('Setup verification successful.')
        
except Exception as e:
    print(f'Setup Error: {e}')
    sys.exit(1)
"

# Launch Firefox directly to Expenses app My Expenses
ensure_firefox "http://localhost:8069/web#action=hr_expense.hr_expense_actions_my_unsubmitted"

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="