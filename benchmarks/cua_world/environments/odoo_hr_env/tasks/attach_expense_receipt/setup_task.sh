#!/bin/bash
set -e
echo "=== Setting up attach_expense_receipt task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (PostgreSQL stores UTC, so we'll grab UTC timestamp)
date -u +%s > /tmp/task_start_time.txt

# 1. Generate the receipt file
echo "Generating receipt file..."
mkdir -p /home/ga/Documents
# Create a realistic-looking receipt image
convert -size 400x600 xc:white \
    -font DejaVu-Sans -pointsize 20 -fill black \
    -draw "text 120,50 'RESTAURANT'" \
    -draw "text 100,100 '123 Main St, City'" \
    -draw "text 20,180 'Item: Client Lunch'" \
    -draw "text 280,180 '$125.50'" \
    -draw "text 20,220 'Total'" \
    -draw "text 280,220 '$125.50'" \
    -draw "text 100,500 'Thank you!'" \
    /home/ga/Documents/receipt_lunch.jpg

chown ga:ga /home/ga/Documents/receipt_lunch.jpg
chmod 644 /home/ga/Documents/receipt_lunch.jpg

# 2. Create the target expense record via Python/XML-RPC
echo "Creating target expense record..."
python3 << 'PYEOF'
import xmlrpc.client
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find Employee Marc Demo
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', 'ilike', 'Marc Demo']]])
    if not emp_ids:
        print("Error: Marc Demo not found")
        sys.exit(1)
    emp_id = emp_ids[0]

    # Find or Create Expense Product
    prod_ids = models.execute_kw(db, uid, password, 'product.product', 'search', [[['can_be_expensed', '=', True]]], {'limit': 1})
    if not prod_ids:
         prod_id = models.execute_kw(db, uid, password, 'product.product', 'create', [{
            'name': 'General Expense',
            'can_be_expensed': True,
         }])
    else:
        prod_id = prod_ids[0]

    # Clean up any existing "Client Lunch" expenses for Marc Demo to avoid ambiguity
    existing_ids = models.execute_kw(db, uid, password, 'hr.expense', 'search', 
        [[['name', '=', 'Client Lunch'], ['employee_id', '=', emp_id]]])
    if existing_ids:
        models.execute_kw(db, uid, password, 'hr.expense', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing expenses.")

    # Create the Expense (Odoo 17 uses total_amount_currency, not unit_amount)
    expense_id = models.execute_kw(db, uid, password, 'hr.expense', 'create', [{
        'name': 'Client Lunch',
        'employee_id': emp_id,
        'product_id': prod_id,
        'total_amount_currency': 125.50,
        'quantity': 1,
        'payment_mode': 'own_account',
        'description': 'Business lunch with client',
    }])
    
    print(f"Created Target Expense ID: {expense_id}")
    
    # Save the ID for the verifier/exporter to check later
    with open('/tmp/target_expense_id.txt', 'w') as f:
        f.write(str(expense_id))

except Exception as e:
    print(f"Error creating expense: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# 3. Ensure Firefox is open and on the Expenses page
# We send them to the main Expenses view; they have to find the specific record.
ensure_firefox "http://localhost:8069/web#action=hr_expense.hr_expense_actions_my_unsubmitted"
sleep 5

# 4. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="