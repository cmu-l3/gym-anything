#!/bin/bash
echo "=== Setting up bill_reimbursable_expense task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager is running
wait_for_manager 60

# We need to ensure the "Billable Expenses" module is DISABLED initially to test the agent.
# The default setup in manager_env usually enables specific tabs. 
# We will use a python script to ensure it's off or at least record state.
# Since we can't easily "uncheck" via simple API without knowing the exact current config,
# we rely on the fact that standard setup (setup_data.sh) does NOT enable BillableExpenses.
# Standard modules: BankAndCashAccounts, Receipts, Payments, Customers, SalesInvoices, ...
# BillableExpenses is not in the standard list.

# Record initial state of payments to detect changes
# We'll use a python script to grab the current payment count
python3 -c "
import requests, re
try:
    s = requests.Session()
    # Login
    s.post('http://localhost:8080/login', data={'Username': 'administrator'}, allow_redirects=True)
    # Get Business Key
    r = s.get('http://localhost:8080/businesses')
    m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', r.text)
    if not m: m = re.search(r'start\?([^\"&\s]+)', r.text)
    key = m.group(1) if m else ''
    
    # Get Payment Count
    r = s.get(f'http://localhost:8080/payments?{key}')
    count = r.text.count('<tr>') # Rough count of rows
    with open('/tmp/initial_payment_count.txt', 'w') as f:
        f.write(str(count))
except:
    pass
" 2>/dev/null || echo "0" > /tmp/initial_payment_count.txt

# Open Manager.io at the Summary page (Dashboard)
echo "Opening Manager.io at Summary page..."
open_manager_at "summary"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="