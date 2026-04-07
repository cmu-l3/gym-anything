#!/bin/bash
echo "=== Exporting submit_expense_on_behalf result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read start time
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to query Odoo via XML-RPC and export result to JSON
# We look for expenses created AFTER the task start time matching the description
python3 << PYTHON_EOF
import xmlrpc.client
import json
import datetime
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'
task_start_ts = float($START_TIME)

result = {
    "expense_found": False,
    "employee_name": None,
    "amount": 0.0,
    "product_name": None,
    "created_during_task": False,
    "description_match": False,
    "candidates_found": 0
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Search for expenses with the specific description
    # ILIKE is case-insensitive
    domain = [['name', 'ilike', 'Client Dinner with Acme Corp']]
    expense_ids = models.execute_kw(db, uid, password, 'hr.expense', 'search', [domain])
    
    result["candidates_found"] = len(expense_ids)

    if expense_ids:
        # Read the most recent one
        # sort desc by id
        expense_ids.sort(reverse=True)
        target_id = expense_ids[0]
        
        fields = ['name', 'total_amount', 'employee_id', 'product_id', 'create_date']
        data = models.execute_kw(db, uid, password, 'hr.expense', 'read', [[target_id], fields])[0]
        
        # Check timestamp
        create_date_str = data.get('create_date') # e.g. "2023-10-27 10:00:00"
        # Odoo stores in UTC without tzinfo usually. 
        # Assume server time is roughly synced or check relative delta if needed.
        # Simple check: timestamp comparison
        create_dt = datetime.datetime.strptime(create_date_str, "%Y-%m-%d %H:%M:%S")
        # Adjust for potential timezone offset if system clock differs from Odoo DB clock
        # Here we assume both are in container and synced.
        
        result["expense_found"] = True
        result["description_match"] = "Client Dinner with Acme Corp" in data.get("name", "")
        result["amount"] = data.get("total_amount", 0.0)
        
        # employee_id is [id, "Name"]
        emp = data.get("employee_id")
        result["employee_name"] = emp[1] if emp else None
        
        # product_id is [id, "Name"]
        prod = data.get("product_id")
        result["product_name"] = prod[1] if prod else None
        
        # Check against start time
        if create_dt.timestamp() >= task_start_ts:
            result["created_during_task"] = True
        else:
            # Fallback for slight clock skew: allow 60s tolerance before start
            if create_dt.timestamp() >= (task_start_ts - 60):
                result["created_during_task"] = True

except Exception as e:
    result["error"] = str(e)

# Write to JSON file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)

print("Export finished.")
PYTHON_EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="