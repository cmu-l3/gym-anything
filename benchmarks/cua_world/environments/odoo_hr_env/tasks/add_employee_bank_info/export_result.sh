#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting add_employee_bank_info results ==="

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for the final state of Anita Oliver
echo "Querying Odoo database..."
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "employee_found": False,
    "bank_account_linked": False,
    "acc_number": None,
    "bank_name": None,
    "record_create_date": None,
    "task_start_time": int("$TASK_START"),
    "timestamp_check_passed": False
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find Anita Oliver
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Anita Oliver']]])
    
    if emp_ids:
        result["employee_found"] = True
        emp_data = models.execute_kw(db, uid, password, 'hr.employee', 'read', [emp_ids[0], ['bank_account_id']])
        
        # bank_account_id is typically [id, name] or False
        bank_acc_field = emp_data[0]['bank_account_id']
        
        if bank_acc_field:
            result["bank_account_linked"] = True
            bank_acc_id = bank_acc_field[0]
            
            # Read the bank account record (res.partner.bank)
            acc_data = models.execute_kw(db, uid, password, 'res.partner.bank', 'read', [bank_acc_id, ['acc_number', 'bank_id', 'create_date']])
            
            if acc_data:
                record = acc_data[0]
                result["acc_number"] = record['acc_number']
                result["record_create_date"] = record['create_date']
                
                # Check timestamp (Odoo returns string "YYYY-MM-DD HH:MM:SS")
                try:
                    create_dt = datetime.strptime(record['create_date'], "%Y-%m-%d %H:%M:%S")
                    if create_dt.timestamp() > result["task_start_time"]:
                        result["timestamp_check_passed"] = True
                except:
                    pass # Keep false if parsing fails

                # Read the bank entity (res.bank)
                bank_field = record['bank_id'] # [id, name] or False
                if bank_field:
                    result["bank_name"] = bank_field[1]

except Exception as e:
    result["error"] = str(e)

# Write result to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYTHON_EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="