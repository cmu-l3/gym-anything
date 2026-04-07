#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up add_employee_bank_info task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Odoo is ready
echo "Waiting for Odoo to be responsive..."
for i in {1..30}; do
    if curl -s http://localhost:8069/web/health >/dev/null; then
        break
    fi
    sleep 1
done

# Reset data state: 
# 1. Unlink any existing bank account from Anita Oliver
# 2. Delete "Safe Bank" if it exists (to force agent to create it)
echo "Resetting data via XML-RPC..."
python3 << PYTHON_EOF
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("Auth failed")
        sys.exit(1)
        
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Find Anita Oliver
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Anita Oliver']]])
    if not emp_ids:
        print("Error: Anita Oliver not found in demo data.")
        sys.exit(1)
    
    emp_id = emp_ids[0]
    
    # 2. Clear bank_account_id on employee
    # We don't necessarily delete the bank account record itself, just unlink it from the employee
    # to simulate the "no bank account configured" state.
    models.execute_kw(db, uid, password, 'hr.employee', 'write', [[emp_id], {'bank_account_id': False}])
    print(f"Cleared bank account for Employee ID {emp_id} (Anita Oliver).")

    # 3. Clean up 'Safe Bank' records to ensure clean creation test
    # Find bank accounts with this number first
    acc_ids = models.execute_kw(db, uid, password, 'res.partner.bank', 'search', [[['acc_number', '=', '9876543210']]])
    if acc_ids:
        models.execute_kw(db, uid, password, 'res.partner.bank', 'unlink', [acc_ids])
        print(f"Removed existing bank accounts with number 9876543210.")

    # Find the bank entity itself
    bank_ids = models.execute_kw(db, uid, password, 'res.bank', 'search', [[['name', '=', 'Safe Bank']]])
    if bank_ids:
        models.execute_kw(db, uid, password, 'res.bank', 'unlink', [bank_ids])
        print(f"Removed stale 'Safe Bank' records.")

except Exception as e:
    print(f"Setup failed: {e}")
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and navigate to Employees app
# We start at the main employees list so the agent has to search/find the employee
echo "Launching Firefox..."
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"

# Capture initial state
echo "Capturing initial screenshot..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="