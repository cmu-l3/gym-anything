#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting approve_expense_report results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve Initial State
INITIAL_ID="0"
INITIAL_STATE_VAL="unknown"
if [ -f /tmp/initial_state.json ]; then
    INITIAL_ID=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('id', 0))")
    INITIAL_STATE_VAL=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_state', 'unknown'))")
fi

# 3. Check Current State via XML-RPC
# We look for the exact same ID we created to prevent the agent from creating a duplicate
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    'found': False,
    'id': 0,
    'current_state': 'unknown',
    'total_amount': 0.0,
    'employee_match': False,
    'initial_id_match': False,
    'initial_state': '$INITIAL_STATE_VAL',
    'timestamp': '$(date +%s)'
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Search for the report by ID if we have it, otherwise by name
    target_id = int('$INITIAL_ID')
    
    # Read the specific record
    if target_id > 0:
        sheets = models.execute_kw(db, uid, password, 'hr.expense.sheet', 'read', 
            [[target_id]], {'fields': ['id', 'name', 'state', 'total_amount', 'employee_id']})
    else:
        # Fallback search if setup failed to record ID (unlikely)
        s_ids = models.execute_kw(db, uid, password, 'hr.expense.sheet', 'search',
            [[['name', '=', 'Q4 Digital Marketing Conference'], ['employee_id.name', '=', 'Eli Lambert']]])
        if s_ids:
            sheets = models.execute_kw(db, uid, password, 'hr.expense.sheet', 'read',
                [s_ids], {'fields': ['id', 'name', 'state', 'total_amount', 'employee_id']})
        else:
            sheets = []

    if sheets:
        sheet = sheets[0]
        result['found'] = True
        result['id'] = sheet['id']
        result['current_state'] = sheet['state']
        result['total_amount'] = sheet['total_amount']
        
        # Check employee (tuple: [id, name])
        emp_name = sheet['employee_id'][1] if sheet['employee_id'] else ""
        if 'Eli Lambert' in emp_name:
            result['employee_match'] = True
            
        # Check if it's the same record we created
        if target_id > 0 and sheet['id'] == target_id:
            result['initial_id_match'] = True

except Exception as e:
    result['error'] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)

PYTHON_EOF

# 4. Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json